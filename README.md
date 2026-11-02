# eFixMate Admin (mobile)

Flutter app with every feature of the web admin panel (`efixmate/client/src/pages/admin`).
It talks only to the existing server APIs. No new endpoints were added.

## Run

```
flutter pub get
flutter run
```

## Server

Long-press the logo on the login screen to switch servers: Live (`api.efixmate.com`),
Dev (`dev.api.efixmate.com`), or Local (default `http://10.0.2.2:5000` for the emulator;
on a real phone use `adb reverse tcp:5000 tcp:5000` or enter your PC's LAN IP).
The default for a fresh install is `AppConfig.env` in `lib/core/config.dart`.

## Login

Enter the admin's personal login link (`…/login/<admin id>`) or just the admin ID,
then email + password (+ 6-digit code if 2FA is on). The session is the same
`efm_a_token` cookie the web panel uses, kept in a persistent cookie jar.
Sensitive actions (refund approve/retry/resolve) ask for the password again
(server step-up), same as the web.

## Structure

- `lib/core/` — API client (cookies, step-up retry), session + menu/privilege checks, formatters
- `lib/ui/` — theme, shared widgets, infinite list, field-driven form builder
- `lib/routes.dart` — one native screen per web `menu_path`; the Menu tab only shows what the admin's role allows
- `lib/screens/` — one folder per module (bookings, users, technicians, masters, finance, marketing, support, operations, admin, settings)
- `assets/admin_guides.json` — Help & Guides content exported from `adminGuideContent.ts`
