# Gitea + Redmine lokalnie

Obie aplikacje korzystaja z jednego kontenera PostgreSQL 16. Kazda ma osobna
baze, uzytkownika bez uprawnien administratora i losowe haslo.
To prosty punkt wyjscia dla zespolu deweloperskiego okolo 10 osob; rzeczywiste
zapotrzebowanie na zasoby zalezy od wielkosci repozytoriow i obciazenia.

## Wymagania i start

Wymagany Linux, Docker Engine z Compose v2 i OpenSSL (polecenie `openssl`).
Polecenia wykonuj w tym katalogu, w powloce systemowej:

```sh
sh initialize-local-env.sh
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

Skrypt tworzy prywatny `.env` lub dopisuje brakujace sekrety, zachowujac
istniejace wartosci. Mozna uruchamiac go ponownie. Nie usuwaj sekretow
uzywanych juz przez bazy: wygenerowane nowe hasla nie zmienia hasel w bazach.
Plik `.env` otrzymuje uprawnienia `600` (odczyt i zapis tylko dla wlasciciela).
Skrypt dziala rowniez wywolany z innego katalogu; zapisuje `.env` obok siebie.
Nie wymaga `chmod +x`, gdy jest uruchamiany przez `sh`.

Pierwszy start Redmine moze potrwac kilka minut ze wzgledu na migracje bazy.
Status `running` nie oznacza jeszcze gotowosci aplikacji. Sprawdz:

```sh
curl --fail --head http://localhost:13000/
curl --fail --head http://localhost:13001/
docker compose logs --tail 100 gitea redmine
```

## Adresy i pierwsze logowanie

| Usluga | Adres |
| --- | --- |
| Gitea WWW | http://localhost:13000 |
| Gitea SSH | `ssh://git@localhost:12222/OWNER/REPO.git` |
| Redmine WWW | http://localhost:13001 |

- Gitea: dokoncz instalacje w przegladarce. Baza PostgreSQL jest juz
  skonfigurowana przez zmienne srodowiskowe. Rozwin sekcje konta administratora
  i utworz je podczas instalacji; publiczna rejestracja jest wylaczona.
- Redmine: domyslne logowanie to `admin` / `admin`. Od razu zmien haslo.
- Gitea SSH: dodaj swoj klucz publiczny w ustawieniach konta.

Adres `localhost` oznacza komputer, na ktorym dziala Docker, a nie komputery
pozostalych czlonkow zespolu. Dla dostepu 10 osob pozostaw porty lokalne
i zapewnij dostep przez tunele SSH, VPN z odpowiednim proxy lub reverse proxy
z HTTPS i kontrola dostepu. Przy udostepnieniu przez proxy zmien tez
`GITEA__server__ROOT_URL`, `DOMAIN` i ustawienia SSH na adresy dostepne zespolowi.
Ten plik sam nie konfiguruje zdalnego dostepu.

## Oddzielenie od produkcji

- Wszystkie opublikowane porty sa przypiete do `127.0.0.1`, nie do `0.0.0.0`.
  Nie sa celowo udostepniane przez adres LAN ani IPv6. Jesli system rozwiazuje
  `localhost` tylko na IPv6, otworz `http://127.0.0.1:13000` lub
  `http://127.0.0.1:13001`.
- PostgreSQL nie publikuje portow hosta; nie zajmuje produkcyjnego `5432`.
  Nie korzysta z instancji produkcyjnej.
- Projekt Compose ma nazwe `greg-local-tools`; sieci, kontenery i wolumeny sa
  tworzone w jego przestrzeni nazw. Nie uzywaj tej nazwy dla innych stosow.
  Nie ma `container_name`, sieci zewnetrznych, montowania katalogow produkcyjnych
  ani gniazda Dockera.
- Gitea i Redmine sa w osobnych sieciach; PostgreSQL nalezy do obu.
  Kazdy uzytkownik bazy ma dostep tylko do swojej bazy aplikacyjnej.
  To nie sa sieci `internal`: aplikacje moga laczyc sie na zewnatrz, np. przy
  imporcie repozytoriow. To izolacja zasobow stosu, nie zapora ruchu wychodzacego.
- Limity: Gitea 1 CPU / 1 GiB RAM, Redmine 1 CPU / 1.5 GiB RAM,
  PostgreSQL 0.5 CPU / 512 MiB RAM. Laczny limit to 2.5 CPU / 3 GiB RAM;
  to limity maksymalne, nie rezerwacja zasobow.
- Restart lub przeciazenie wspolnego PostgreSQL dotknie obu aplikacji.
- Logi sa rotowane: 3 pliki po 10 MiB na kontener.

**To nie gwarantuje braku wplywu na produkcje:** kontenery nadal dziela hosta,
dysk i silnik Docker. Dane repozytoriow, zalacznikow i baz nie maja limitu
rozmiaru. Zapewnij zapas zasobow i monitoruj wolne miejsce. Na wspolnym hoscie
uzywaj aktualnego Dockera (co najmniej 28; starsze wersje mialy ograniczenia
izolacji portow publikowanych na localhost). Dla pelnej separacji uzyj osobnej
maszyny/VM.

Przed startem na docelowym hoscie sprawdz, czy porty `13000`, `13001`, `12222`
sa wolne. Przy konflikcie zmien porty w `compose.yaml`; dla Gitea zmien tez
`GITEA__server__ROOT_URL` i/lub `GITEA__server__SSH_PORT`.

## Zatrzymywanie, dane i aktualizacje

### Zmiana z poprzedniej konfiguracji dwoch baz

Nowy stos uzywa wolumenu `postgres-data`. Skrypt `postgres-init.sh` tworzy
role i bazy tylko przy pierwszej inicjalizacji pustego wolumenu.
Uruchom ponownie `sh initialize-local-env.sh`, aby dopisac haslo administratora
PostgreSQL bez zmiany hasel aplikacji.

Jesli poprzedni stos byl juz uruchomiony i zawiera dane, **nie uruchamiaj nowej
konfiguracji przed migracja**. Wykonaj kopie obu baz i zatrzymaj poprzedni stos
przy uzyciu jego starego pliku Compose. Nastepnie odtworz obie bazy we wspolnej
instancji przed uruchomieniem aplikacji, zachowujac wlascicieli `gitea` i
`redmine`. Stare wolumeny nie sa automatycznie przenoszone ani usuwane.
Nie usuwaj ich przed sprawdzeniem migracji.

### Biezaca obsluga

```sh
docker compose stop
docker compose start
```

`docker compose down` usuwa kontenery i sieci tego projektu, ale zachowuje dane.
**Nie dodawaj `--volumes` / `-v`, jesli chcesz zachowac dane.**
Nie uzywaj globalnych polecen typu `docker system prune` na hoscie produkcyjnym.

Zachowaj `.env` oraz kopie baz (np. wykonane `pg_dump`) i wolumenow `gitea-data`
oraz `redmine-files`. Ponizszy skrypt wykonuje kopie na zywo z opisanym
ograniczeniem spojnosci. Nie kopiuj dzialajacego katalogu danych PostgreSQL
jako zwyklego backupu.
Zmiana hasel w `.env` nie zmienia hasel w juz zainicjalizowanych bazach.

Obrazy sledza linie Gitea `1`, Redmine `6.1` i PostgreSQL `16`, bez tagu
`latest`. Tagi moga wskazywac nowsze wydania: nie aktualizuj automatycznie;
przed ponownym `pull` wykonaj backup i sprawdz informacje o migracjach.
Jesli potrzebujesz identycznych wdrozen, przypnij przetestowane obrazy po digest.
Nie zmieniaj glownej wersji PostgreSQL bez migracji danych.

Stos nie zawiera integracji Gitea z Redmine ani konfiguracji poczty.

## Automatyczny backup bez zatrzymywania uslug

`backup.sh` wykonuje pelne kopie cztery razy na dobe: 00:00, 06:00, 12:00,
18:00 wedlug strefy czasowej serwera. Zachowuje 7 dni lokalnie i 30 dni
na Google Drive. Nie wykonuje `stop`, `restart` ani `down`.

W kopii znajduja sie:

- zrzuty `pg_dump` obu baz w formacie custom;
- cale `/data` Gitea, w tym repozytoria, konfiguracja i klucze SSH;
- zalaczniki Redmine z `/usr/src/redmine/files`;
- `.env`, plik Compose, skrypty inicjalizacji, identyfikatory obrazow
  i sumy SHA-256.

Kazdy zrzut bazy jest spojny, ale pliki sa kopiowane na zywo, po zrzutach.
**To nie jest atomowy snapshot calego stosu.** Zmiany repozytoriow i zalacznikow
w czasie kopii moga powodowac rozbieznosci; narzedzie tar nie wykryje wszystkich
takich sytuacji. Wykryty blad kopiowania powoduje niepowodzenie backupu.
Backup obciaza CPU, dysk i siec, mimo ze nie zatrzymuje aplikacji.

### 1. Google Drive i szyfrowanie

Na serwerze zainstaluj `rclone`, Bash i `flock` (pakiet `util-linux`).
Uzyj konta systemowego z dostepem do Dockera i katalogu stosu.
Na Debianie/Ubuntu:

```sh
sudo apt-get update
sudo apt-get install rclone util-linux
rclone config
```

W kreatorze rclone:

1. Utworz remote `gdrive` typu `drive` i autoryzuj swoje konto Google.
   Na serwerze bez przegladarki wybierz autoryzacje przez inny komputer
   zgodnie z instrukcjami kreatora (`rclone authorize`).
2. Utworz remote `gdrive-backup` typu `crypt`, wskazujacy na
   `gdrive:greg-backups-encrypted`. Wlacz szyfrowanie nazw plikow (`standard`)
   i katalogow oraz ustaw silne haslo szyfrowania i salt.
3. Zapisz haslo/salt i konfiguracje rclone w osobnym, bezpiecznym miejscu
   poza tym serwerem. Bez nich zaszyfrowanych kopii nie da sie odzyskac.

Konfiguruj i uruchamiaj rclone jako **ten sam uzytkownik**, ktory bedzie mial
crona. Nie konfiguruj go jako zwykly uzytkownik, a potem nie uruchamiaj backupu
przez `sudo` bez skonfigurowania rclone dla roota.
Sciezke prywatnego pliku konfiguracji pokazuje `rclone config file`.

Skrypt wymaga remote typu `crypt`; dane, w tym hasla, sa szyfrowane przed
wyslaniem do Google. **Kopie lokalne nie sa zaszyfrowane:** katalog `backups`
ma uprawnienia `700`, pliki `600`. Rozwaz szyfrowanie dysku serwera.
Konfiguracja rclone i klucze szyfrowania nie sa dolaczane do backupu.
Przed wyslaniem danych klienta na prywatny Drive uzyskaj jego zgode.

### 2. Konfiguracja i pierwszy backup

W katalogu stosu:

```sh
cp backup.conf.example .backup.conf
chmod 600 .backup.conf
# W razie potrzeby zmien RCLONE_DEST w .backup.conf.
bash backup.sh
```

Docelowy katalog musi byc dedykowany temu stosowi i serwerowi. Skrypt nie uzywa
`sync` ani nie czysci calego Drive. Retencja usuwa tylko pliki tego formatu
`backup-DATA-SUFIKS.tar.gz` bezposrednio w skonfigurowanym katalogu.

Skrypt sprawdza format zrzutow i archiwow, a po uploadzie pobiera kopie
z powrotem strumieniowo i porownuje SHA-256. To oznacza dodatkowy transfer
wielkosci backupu. **Nie zastepuje to testu odtworzenia.**
Dopiero po poprawnej weryfikacji uruchamia retencje.

Przy bledzie konczy sie kodem niezerowym i wypisuje `ERROR`. Gotowa lokalna
kopia pozostaje przy bledzie uploadu. Niedokonczony plik `.partial` po bledzie
pakowania trzeba sprawdzic i usunac recznie; nie jest uznawany za gotowy backup.
Blokada `flock` nie dopuszcza rownoleglych uruchomien. Przerwane przebiegi
nie sa automatycznie wznawiane; kolejny termin tworzy nowa pelna kopie.

### 3. Cron

Po udanym recznym backupie skopiuj wpis z `backup.cron.example` do
`crontab -e`, zmieniajac `/opt/greg-infra` na rzeczywisty katalog stosu.
Nie nadpisuj calego crontaba, jesli sa w nim inne zadania.

```cron
0 0,6,12,18 * * * /bin/bash /opt/greg-infra/backup.sh >> /opt/greg-infra/backup.log 2>&1
```

W crontabie ustaw rowniez `PATH` podany w pliku przykladowym.
Sprawdzaj `backup.log` oraz obecnosc swiezych kopii; skonfiguruj monitoring
braku sukcesu/bledu i rotacje logu przez systemowy logrotate.
Przy bledach retencja nie rusza: monitoruj wolne miejsce, bo kopie moga
przekroczyc zakladane 7/30 dni. Nie kasuj lokalnych kopii, gdy chmura nie dziala.

### 4. Zmiana Google Drive na konto klienta

Dodaj w `rclone config` nowe konto `drive` i nowy remote `crypt` wskazujacy
na jego katalog. Zmien `RCLONE_DEST` w `.backup.conf`, wykonaj reczny backup
i sprawdz odtworzenie. Cron i skrypt pozostaja bez zmian.
Stare kopie i klucze zachowaj do czasu potwierdzenia migracji; retencja nowego
remote nie usuwa danych ze starego konta. Przenoszac stare kopie pomiedzy
remote `crypt`, uzywaj rclone przez odszyfrowane remote albo zachowaj te same
parametry szyfrowania, jesli kopiujesz zaszyfrowane pliki bezposrednio.

### 5. Test odtworzenia / odtworzenie po awarii

Wykonaj test na **osobnej maszynie/VM**, nie na dzialajacym stosie. Ponizsze
polecenia zakladaja pusty stos i wolne porty. Uzyj zgodnych wersji obrazow;
`images.txt` zawiera identyfikatory z chwili kopii, ale same obrazy nie sa
archiwizowane. Przy starszej kopii nie aktualizuj aplikacji przed odtworzeniem.

```sh
umask 077
rclone copyto gdrive-backup:greg-local-tools/server-1/NAZWA_BACKUPU.tar.gz restore.tar.gz
mkdir restore-data
tar -xzf restore.tar.gz -C restore-data
cd restore-data
sha256sum -c SHA256SUMS

# Nie generuj nowych hasel: .env zostal odtworzony z kopii.
docker compose up -d --wait postgres
docker compose exec -T postgres pg_restore --username=postgres --dbname=gitea \
  --clean --if-exists --no-owner --role=gitea --exit-on-error < gitea.dump
docker compose exec -T postgres pg_restore --username=postgres --dbname=redmine \
  --clean --if-exists --no-owner --role=redmine --exit-on-error < redmine.dump

# Jednorazowe kontenery przywracaja pliki, nie uruchamiaja aplikacji.
docker compose run --rm --no-deps -T --user root --entrypoint tar gitea \
  -xzf - -C /data < gitea-data.tar.gz
docker compose run --rm --no-deps -T --user root --entrypoint tar redmine \
  -xzf - -C /usr/src/redmine/files < redmine-files.tar.gz
docker compose up -d
```

Sprawdz logowanie, projekty, pobranie/klonowanie repozytorium, LFS (jesli
uzywasz), zalaczniki i klucze SSH. Zapisz wynik testu. Dopiero poprawne
odtworzenie potwierdza uzytecznosc kopii.
