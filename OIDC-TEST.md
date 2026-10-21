# Test Redmine 7.0.2 + Google OIDC

To eksperymentalna instancja do weryfikacji pluginu, nie gotowe wdrozenie SSO.
Plugin `enricohuang/redmine_oidc` deklaruje kompatybilnosc z Redmine 5/6,
nie z 7. Obraz przypina jego kod do commita
`3d3eaaf6c17cd37b861306938fe33baabdd7b690`, aby test byl powtarzalny.
Start obrazu, migracje i rzeczywisty przeplyw Google wymagaja testu na serwerze.

## Start

Skopiuj rowniez `Dockerfile.redmine-oidc-test`, `.dockerignore` i
`compose.oidc-test.yaml` do katalogu projektu. Korzystamy z istniejacego `.env`,
ale nie z istniejacych baz ani wolumenow. Nie uruchamiaj obu instancji
jednoczesnie w CT z 1 GiB RAM, jezeli nie ma zapasu pamieci.

```sh
docker compose -f compose.oidc-test.yaml config --quiet
docker compose -f compose.oidc-test.yaml up -d --build
docker compose -f compose.oidc-test.yaml logs --tail 150 postgres redmine
```

Uzywaj tylko `-f compose.oidc-test.yaml`, bez laczenia z glownym Compose.
Projekt ma nazwe `greg-oidc-test`, wlasna siec, dwie wlasne przestrzenie
wolumenow i port `127.0.0.1:13002`. Baza nie publikuje portu hosta.
Celowo brak limitow CPU/RAM ze wzgledu na testowy LXC z uszkodzona obsluga
cgroups; caly LXC nadal ogranicza zasoby. Konto PostgreSQL jest administratorem
tylko tej oddzielnej instancji testowej, nie bazy glownego stosu.
Skrypt backupu glownego stosu nie obejmuje tej instancji.

Na swoim komputerze otworz tunel:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 13002:127.0.0.1:13002 user@SERWER
```

Otworz http://localhost:13002, zaloguj sie jako `admin` / `admin` i od razu
zmien haslo. Sprawdz wersje aplikacji i obecnosc pluginu w Administracja >
Wtyczki. Bledy startu/migracji oznaczaja, ze zgodnosc nie zostala potwierdzona.

## Google

W Google Cloud dodaj klienta OAuth typu **Web application**, z callbackiem:

```text
http://localhost:13002/oidc/callback
```

Jesli aplikacja Google jest External / Testing, dodaj konta do Test users.
Nie traktuj tej listy jako docelowej kontroli dostepu po publikacji aplikacji.

W Redmine, Administracja > Wtyczki > Redmine OIDC > Konfiguruj:

- Issuer URL: `https://accounts.google.com`
- Client ID i Client Secret: z klienta Google; nie zapisuj sekretu w Git.
- Scopes: `openid email profile`
- Auto-registration: **wylaczone**
- Email Matching: **wlaczone tylko do kontrolowanego testu konta**
- Auto-login: na poczatek **wylaczone**, pozostaw awaryjne logowanie lokalne.

Ta konfiguracja nie implementuje listy dozwolonych adresow. Wylaczenie
automatycznej rejestracji ogranicza tworzenie kont, ale nie zastapi docelowej
polityki autoryzacji. Nie wlaczaj automatycznej rejestracji dla dowolnego Google.

## Kryteria akceptacji przed wdrozeniem

1. Utworz zwykle, aktywne konto testowe Redmine z adresem wybranego konta Google.
2. W osobnym oknie przegladarki sprawdz logowanie Google, powiazanie konta,
   wylogowanie i ponowne logowanie.
3. Sprawdz, czy konto Google bez konta Redmine nie moze sie zarejestrowac.
4. Zablokuj konto testowe w Redmine i sprawdz odmowe kolejnego logowania.
5. Sprawdz odmowe przy anulowaniu zgody Google, blednym callbacku oraz
   zachowanie juz otwartej sesji po zablokowaniu konta.
6. Zrestartuj tylko testowa usluge i sprawdz trwalosc konfiguracji/pluginu:

   ```sh
   docker compose -f compose.oidc-test.yaml restart redmine
   ```

To test kompatybilnosci, nie potwierdzenie poprawnosci calej integracji.
Przed docelowym wlaczeniem potrzebna jest jeszcze wspolna decyzja o tym,
gdzie egzekwowac liste e-maili i jak odbierac dostep istniejacym sesjom,
tokenom i kluczom SSH Gitea. Google OIDC nie uniewaznia ich automatycznie.

## Zatrzymanie

```sh
docker compose -f compose.oidc-test.yaml down
```

To zachowuje dane testowe. Nie uzywaj `-v`, jezeli chcesz zachowac wyniki.
Glowny Compose nadal uzywa Redmine 6.1. Docelowe callbacki po udanym wdrozeniu
beda uzywaly `localhost:13001` dla Redmine i `localhost:13000` dla Gitea.
