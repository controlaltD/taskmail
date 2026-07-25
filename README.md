# TaskMail

Fiatalos, AI-alapú levelező app Windows / macOS / iOS / Android platformokon.
Az AI kategorizálja a beérkező leveleket, felismeri bennük a teendőket, és
Trello-szerű kanban board-on jeleníti meg őket az appon belül. A board
önállóan is működik, de a kártyák kiválasztva átküldhetők a **már meglévő,
éles ServeOS Kanban ("Feladatok") moduljába** — ugyanazokkal a mezőkkel és
kártyastílussal, mint amit a ServeOS csapat már használ.

## Tech stack

| Réteg | Technológia |
|---|---|
| Kliens | Flutter (iOS, Android, macOS, Windows, Linux) |
| Állapotkezelés | Riverpod |
| Navigáció | go_router |
| Backend | Supabase (Postgres + Auth) — **ugyanaz az instance**, mint a `serveos`/`serveos_admin` |
| AI | Claude API (Anthropic), tool-use structured output |
| Email | Gmail API + Microsoft Graph API, OAuth2 |
| Szerver logika | Supabase Edge Functions (Deno) — nincs külön always-on backend |

## Miért közös Supabase instance?

A TaskMail a ServeOS fiókkal jelentkeztet be (`auth.users`), és a
`venue_users` táblát (lásd `serveos_admin` migrációja) használja a
venue-választáshoz, amikor egy kártyát átküldesz a ServeOS Kanban táblájára.
A ServeOS `tasks` táblájának RLS-e jelenleg permisszív, így a TaskMail
kliens közvetlenül tud írni bele — **nincs szükség külön backend hídra** a
szinkronhoz. A TaskMail saját táblái `taskmail_` prefixet kapnak, hogy ne
ütközzenek a ServeOS saját tábláival (`tasks`, `users`, `employees`, `venues`).

## Gyors indítás

```bash
cd app
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

A Gmail/Outlook `client_id`-kat nem kell a kliensnek átadni: az engedélykérő
URL-t az `oauth-start` Edge Function állítja össze szerveroldalon.

A `SUPABASE_URL`/`SUPABASE_ANON_KEY` **ugyanaz**, mint a `serveos`/
`serveos_admin` `.env`-jében — így közös a bejelentkezés.

## Supabase beállítás

1. Supabase Dashboard → SQL Editor → futtasd sorrendben a
   `supabase/migrations/0001_taskmail_schema.sql`, majd a
   `0002_oauth_state.sql` tartalmát (ugyanabban a projektben, mint ahol a
   `serveos_admin`/`serveos` migrációi már lefutottak — a `venues`/
   `venue_users` tábláknak léteznie kell előtte).
2. Edge Function secrets beállítása (Dashboard → Edge Functions → Secrets,
   vagy `supabase secrets set`):
   - `ANTHROPIC_API_KEY` — Claude API kulcs
   - `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` — Google Cloud OAuth app
   - `MICROSOFT_CLIENT_ID` / `MICROSOFT_CLIENT_SECRET` — Microsoft Entra app
   - `TOKEN_ENCRYPTION_KEY` — `openssl rand -base64 32` kimenete (email OAuth
     tokenek titkosításához)
   - `SYNC_CRON_SECRET` — tetszőleges random string, ami megvédi a
     `sync-emails` endpointot illetéktelen hívástól
   - `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` — ezeket a Supabase
     automatikusan beállítja minden Edge Function számára
3. Edge Functions deploy:
   ```bash
   # Ezt a kliens hívja a saját munkamenetével → JWT-ellenőrzés KELL
   supabase functions deploy oauth-start

   # Ezeket a Google/Microsoft hívja vissza, illetve a cron → nincs kliens-JWT
   supabase functions deploy gmail-oauth-callback --no-verify-jwt
   supabase functions deploy outlook-oauth-callback --no-verify-jwt
   supabase functions deploy sync-emails --no-verify-jwt
   ```
   ⚠️ A `sync-emails` csak akkor ellenőriz jogosultságot, ha a
   `SYNC_CRON_SECRET` be van állítva — ha kimarad, a végpont bárki által
   hívható. A telepítés után ezt feltétlenül ellenőrizd.
4. `sync-emails` időzítése `pg_cron` + `pg_net`-tel (SQL Editor):
   ```sql
   select cron.schedule(
     'taskmail-sync-emails',
     '*/5 * * * *',
     $$
     select net.http_post(
       url := 'https://<project-ref>.supabase.co/functions/v1/sync-emails',
       headers := jsonb_build_object('Authorization', 'Bearer <SYNC_CRON_SECRET>')
     );
     $$
   );
   ```

## Google Cloud / Microsoft Entra OAuth app

- **Google Cloud Console** → új projekt vagy meglévő → OAuth consent screen →
  OAuth Client ID (Web application) → Authorized redirect URI:
  `https://<project-ref>.supabase.co/functions/v1/gmail-oauth-callback`
  → Scope: `https://www.googleapis.com/auth/gmail.readonly`
- **Microsoft Entra admin center** → App registrations → New registration →
  Redirect URI (Web):
  `https://<project-ref>.supabase.co/functions/v1/outlook-oauth-callback`
  → API permissions: `Mail.Read`, `offline_access`

A mobil/desktop appok `hu.serveos.taskmail://oauth-callback` custom URL
scheme-mel kapják vissza az irányítást (`flutter_web_auth_2`) — ezt a
callback Edge Function-ök végén történő redirect adja vissza, miután a
code→token cserét elvégezték.

## Projekt struktúra

```
taskmail/
├── app/                     — Flutter kliens
│   └── lib/
│       ├── core/            — theme, router, supabase kliens, env config
│       ├── models/          — taskmail_task, board, email_message, email_account, serveos_venue
│       └── features/
│           ├── auth/        — bejelentkezés (közös ServeOS Supabase auth)
│           ├── inbox/       — AI-kategorizált levéllista
│           ├── board/       — kanban board + ServeOS szinkron
│           └── accounts/    — Gmail/Outlook összekötés + ServeOS venue kapcsolat
└── supabase/
    ├── migrations/          — taskmail_ prefixű saját táblák
    └── functions/           — OAuth callbackek + AI email-sync (Edge Functions)
```

## ServeOS szinkron — hogyan működik

Egy board kártyán a **"Küldés ServeOS-be"** gomb megnyit egy venue-választót
(a bejelentkezett fiók `venue_users` kapcsolatai alapján). Kiválasztás után a
Flutter app közvetlenül beszúr egy sort a meglévő, éles ServeOS `tasks`
táblájába — pontosan azokkal a mezőkkel (`title`, `description`, `col`,
`priority`, `label`, `assignees`, `due_date`, `checklist`, `comments`,
`venue_id`), amiket a ServeOS `FeladatokBoard` már ismer, úgyhogy a kártya
változtatás nélkül, natívan jelenik meg ott. A TaskMail oldali kártyára
visszaírjuk a kapott ServeOS `task_id`-t, hogy tudjuk, már át van küldve.

**Ez egyirányú (TaskMail → ServeOS), kártyánkénti kézi döntés** — nincs
automatikus tömeges szinkron és nincs visszaszinkron.

## Ismert korlátok / következő lépések

- A `venue_users` táblába jelenleg csak `service_role` tud sort írni — egy
  TaskMail user önmagát nem tudja venue-hoz kötni, ezt egyelőre a ServeOS
  admin panelen keresztül kell provisionolni.
- Outlook/Gmail push webhook helyett v1-ben polling (cron) van — valós idejű
  értesítés helyett néhány perces késleltetéssel jelennek meg az új levelek.
- Kétirányú ServeOS szinkron (ha ott módosítják a kártyát, az ne tükröződjön
  vissza TaskMail-be) nincs implementálva.
- A jelenlegi színpaletta/branding helykitöltő — cserélhető a
  `app/lib/core/theme/app_theme.dart`-ban.
- Ez a projektváz egy olyan környezetben készült, ahol nincs Xcode/Android
  SDK/eszköz — a fizikai build/futtatás minden platformon a fejlesztő gépén
  történő első teszt.
