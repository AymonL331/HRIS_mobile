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

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Hand it to a
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
