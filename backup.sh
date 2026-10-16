#!/bin/bash
set -Eeuo pipefail
umask 077

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
project_dir=$PWD
backup_dir="$project_dir/backups"
stage=

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2
}

cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$stage" ]]; then
        rm -f -- "$stage"/{gitea.dump,redmine.dump,gitea-data.tar.gz,redmine-files.tar.gz,compose.yaml,postgres-init.sh,initialize-local-env.sh,.env,images.txt,SHA256SUMS}
        rmdir -- "$stage"
    fi
    if (( status != 0 )); then
        log "ERROR: backup failed (exit $status). Existing backups were not removed before verification."
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'log "ERROR at line $LINENO: command failed."' ERR
trap 'exit 1' HUP INT TERM

for command in docker rclone flock tar gzip sha256sum mktemp find awk; do
    command -v "$command" >/dev/null || {
        log "ERROR: missing command: $command"
        exit 1
    }
done

if [[ ! -f .backup.conf ]]; then
    log 'ERROR: copy backup.conf.example to .backup.conf and configure an encrypted rclone destination.'
    exit 1
fi
# This is a private shell configuration owned by the backup operator.
source "$project_dir/.backup.conf"
: "${RCLONE_DEST:?Set RCLONE_DEST in .backup.conf}"

if [[ ! "$RCLONE_DEST" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*$ ]]; then
    log 'ERROR: RCLONE_DEST must be remote:dedicated/folder, using letters, numbers, underscores or hyphens.'
    exit 1
fi
remote=${RCLONE_DEST%%:*}
remotes=$(rclone listremotes --long)
if ! awk -v remote="$remote:" '$1 == remote && $2 == "crypt" { found = 1 } END { exit !found }' <<< "$remotes"; then
    log "ERROR: $remote must be an rclone crypt remote. Plaintext cloud backups are not allowed."
    exit 1
fi

mkdir -p -- "$backup_dir"
chmod 700 "$backup_dir"
exec 9>"$backup_dir/.backup.lock"
if ! flock -n 9; then
    log 'ERROR: another backup is already running.'
    exit 1
fi

compose=(docker compose --project-directory "$project_dir" --env-file "$project_dir/.env" -f "$project_dir/compose.yaml")
"${compose[@]}" config --quiet
stage=$(mktemp -d "$backup_dir/.work.XXXXXX")
filename="backup-$(date -u +%Y%m%dT%H%M%SZ)-${stage##*.}.tar.gz"
archive="$backup_dir/$filename"

cp -- compose.yaml postgres-init.sh initialize-local-env.sh .env "$stage/"
for service in postgres gitea redmine; do
    container=$("${compose[@]}" ps -q "$service")
    if [[ ! "$container" =~ ^[a-f0-9]+$ ]]; then
        log "ERROR: expected one running $service container."
        exit 1
    fi
    docker inspect --format '{{.Name}} {{.Config.Image}} {{.Image}}' "$container" >> "$stage/images.txt"
done

log 'Starting live backup. Applications remain running.'
for database in gitea redmine; do
    "${compose[@]}" exec -T postgres pg_dump --username=postgres --format=custom --dbname="$database" > "$stage/$database.dump"
    "${compose[@]}" exec -T postgres pg_restore --list < "$stage/$database.dump" > /dev/null
done

# Any tar error, including a changing file reported by tar, fails this backup.
"${compose[@]}" exec -T --user root gitea tar -czf - -C /data . > "$stage/gitea-data.tar.gz"
"${compose[@]}" exec -T --user root redmine tar -czf - -C /usr/src/redmine/files . > "$stage/redmine-files.tar.gz"
for file in gitea-data.tar.gz redmine-files.tar.gz; do
    gzip -t "$stage/$file"
    tar -tzf "$stage/$file" > /dev/null
done

(
    cd -- "$stage"
    sha256sum gitea.dump redmine.dump gitea-data.tar.gz redmine-files.tar.gz \
        compose.yaml postgres-init.sh initialize-local-env.sh .env images.txt > SHA256SUMS
)
tar -czf "$archive.partial" -C "$stage" .
gzip -t "$archive.partial"
mv -- "$archive.partial" "$archive"
log "Local backup ready: $archive"

rclone copyto "$archive" "$RCLONE_DEST/$filename" --immutable --retries 3
local_hash=$(sha256sum "$archive")
remote_hash=$(rclone cat "$RCLONE_DEST/$filename" | sha256sum)
if [[ "${local_hash%% *}" != "${remote_hash%% *}" ]]; then
    log 'ERROR: uploaded backup failed SHA-256 verification. Retention skipped.'
    exit 1
fi
log 'Encrypted upload verified by downloading and checking SHA-256.'

# Delete only this script's completed backup files, never unrelated remote data.
rclone delete "$RCLONE_DEST" --min-age 30d --max-depth 1 \
    --include '/backup-????????T??????Z-??????.tar.gz'
find "$backup_dir" -maxdepth 1 -type f \
    -name 'backup-????????T??????Z-??????.tar.gz' -mmin +10080 -print -delete
log "SUCCESS: $filename; retention: 7 days locally, 30 days remotely."
