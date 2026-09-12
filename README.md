# HRIS Mobile

The employee time-clock app for the HRIS. Branch employees sign in with the same
credentials as the website and clock in / out from their own phone. **Location is
mandatory**: the app does not run while the phone's location is off, the
permission is missing, or the accuracy is set to Approximate, and every punch
takes a fresh GPS fix that the server checks against the branch worksite.

Only accounts HR has switched on (**Employee profile › Account › Mobile app**)
can sign in. Turning the switch off signs the phone out on its next request.

## What it talks to

The same Node/Express API as the web app — no direct database access. It uses the
mobile-only endpoints added by migrations 057/058 (`/api/me/mobile-clock`,
`/api/me/mobile-clock/status`) plus `/api/auth/*`, `/api/me/location-consent` and
`/api/me/attendance/calendar`. The server holds every rule; the app never grades
attendance itself.

| Environment | Default address | Editable in app |
|---|---|---|
| Main HRIS | `http://192.168.137.1:5000` (the dev PC's hotspot, for now) | yes — Login › Advanced |
| Sandbox | `https://turbine-chamomile-financial.ngrok-free.dev` | yes |

On the Android emulator, the host PC is `10.0.2.2`: set Sandbox to `http://10.0.2.2:5001`
under Login › Advanced to hit a sandbox server running on the PC (debug builds only).

## Who sees what

| Login | Time Clock | Attendance tab |
|---|---|---|
| Employee (mobile switch on) | clock in / out | **Mine** — own DTR, month by month |
| HR-type employee (`attendance:view`) | clock in / out | **Mine / Everyone** switch |
| Super Admin or special account with `attendance:view` | "No employee record" | **Everyone** — the team DTR for a day |

"Everyone" is read-only and is the only console route a mobile token may reach
(`GET /api/attendance/calendar`, still behind the same permission and branch
scope as the website). Pick a day, search by name or code, page through a big
roster; each person shows their badge, punches, place labels and chips (late,
undertime, mobile app, out of range). No coordinates are shown on the phone.

Change the compiled defaults at build time:

```powershell
flutter build apk --release --dart-define=HRIS_MAIN_URL=https://hris.example.com --dart-define=HRIS_SANDBOX_URL=https://sandbox.example.com
```

Cleartext HTTP is allowed only for `192.168.137.1` (and `10.0.2.2` in debug builds);
a production host must be HTTPS.

## Run it

Start the API first (`npm run dev` in `hris/server`, or the sandbox on 5001).

```powershell
cd hris_mobile
flutter emulators --launch Pixel_8_API_36
flutter run
```

Or plug in an Android phone with USB debugging on and `flutter run`. Press `r` for
hot reload, `q` to quit.

On the emulator, set a position with `adb emu geo fix <lng> <lat>`. The sandbox's
Head Office worksite is `adb emu geo fix 121.0175541 14.5513714`.

## Look and feel

The app wears the website's design system. `lib/shared/tokens.dart` carries the web
tokens (`client/src/styles/tokens.css`) verbatim — page and surface colours, the
`#2563eb` primary, the four status sets, the radii and the type scale — for light and
dark; `lib/shared/theme.dart` maps them onto Material 3, and the app follows the
phone's dark mode the way the website follows `prefers-color-scheme`. Shared widgets
under `lib/shared/widgets/` are the web components: `AppCard` (the bordered card with
the soft shadow), `StatusBadge` (the five-tone pill, with the DTR tone mapping from
`attendanceEnums.js`), `MessageBanner` (the alert with the left accent), `BrandMark`
(the "● HRIS" mark), `UserAvatar`, `PageHeader` / `SectionLabel`. Read tokens through
`HrisTokens.of(context)`, never `extension<HrisTokens>()!` — the widget tests mount
screens under a bare `MaterialApp`.

The launcher icon and splash come from the same mark: `tool/brand/make_icons.ps1`
draws the sources into `assets/brand/`, `dart run flutter_launcher_icons` builds the
adaptive icon, and `android/app/src/main/res/values*/splash_colors.xml` carries the
page colour for both modes.

## Checks

```powershell
flutter analyze
flutter test
```

## Release build

Signing uses the upload keystore at `C:\keys\hris-upload.jks`, named by
`android/key.properties` (gitignored). **Back that keystore up** — an APK signed
with a different key cannot update an installed one; every phone would have to
uninstall first.

```powershell
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk` (copied to
`dist/hris-<version>.apk`, gitignored). Hand it to a
branch with these steps: allow "Install unknown apps" for the browser or file
manager, install, open, allow Location → **Precise** → **While using the app**.
Bump `version:` in `pubspec.yaml` before each release (the build number must
increase for an in-place update).

## Layout

```
lib/
  core/      config (environments), http (API client + typed errors), auth (session),
             location (gate + fixes), time (Manila time, server clock)
  features/  auth (login, change password), consent, time_clock, attendance,
             settings, shell (tabs + the location gate)
  shared/    theme, widgets
test/        unit + widget tests (flutter test)
```
