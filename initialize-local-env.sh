#!/bin/sh
set -eu
umask 077

cd -- "$(dirname -- "$0")"

if ! command -v openssl >/dev/null 2>&1; then
    echo 'OpenSSL is required to generate secrets. Install openssl and retry.' >&2
    exit 1
fi

if [ -L .env ]; then
    echo 'Refusing to modify .env: symbolic links are not supported.' >&2
    exit 1
fi

temp_file=$(mktemp .env.tmp.XXXXXX)
trap 'rm -f -- "$temp_file"' EXIT
trap 'exit 1' HUP INT TERM

if [ -e .env ]; then
    cat .env > "$temp_file"
fi

changed=false
for key in POSTGRES_PASSWORD GITEA_DB_PASSWORD REDMINE_DB_PASSWORD REDMINE_SECRET_KEY_BASE; do
    count=$(awk -v key="$key" '
        index($0, key "=") == 1 {
            count++
            value = substr($0, length(key) + 2)
            if (value ~ /^[[:space:]]*$/) invalid = 1
        }
        END {
            if (count > 1 || invalid) exit 1
            print count + 0
        }
    ' "$temp_file") || {
        echo "Invalid or duplicate $key in .env. Fix it without changing existing database passwords." >&2
        exit 1
    }

    if [ "$count" -eq 0 ]; then
        bytes=32
        if [ "$key" = REDMINE_SECRET_KEY_BASE ]; then
            bytes=64
        fi
        secret=$(openssl rand -hex "$bytes")
        if [ "$changed" = false ] && [ -s "$temp_file" ]; then
            printf '\n' >> "$temp_file"
        fi
        printf '%s=%s\n' "$key" "$secret" >> "$temp_file"
        changed=true
    fi
done

if [ "$changed" = true ]; then
    mv -- "$temp_file" .env
fi
chmod 600 .env

echo '.env is ready; existing secrets were preserved. Keep it private and include it in secure backups.'
