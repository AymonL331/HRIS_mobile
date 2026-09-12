# HRIS Mobile

The employee self-service app for the HRIS. Branch employees sign in with the same
credentials as the website, clock in / out from their own phone, read their own
DTR and read their own payslips. **Location is mandatory**: the app does not run
while the phone's location is off, the permission is missing, or the accuracy is
set to Approximate, and every punch takes a fresh GPS fix that the server checks
against the branch worksite. **Face recognition is mandatory too** — see below.

Only accounts HR has switched on (**Employee profile › Account › Mobile app**)
can sign in. Turning the switch off signs the phone out on its next request.

## What it talks to

The same Node/Express API as the web app — no direct database access. It uses the
mobile-only endpoints added by migrations 057/058 (`/api/me/mobile-clock`,
`/api/me/mobile-clock/status`) plus `/api/auth/*`, `/api/me/location-consent`,
`/api/me/attendance/calendar`, `/api/me/payslips` (`/:id`, `/:id/breakdown`) and
`/api/me/face-clock/challenge` (the liveness challenge every punch must answer).
The server holds every rule; the app never grades attendance and never computes a
peso figure itself — My Payslips renders what payroll already paid, and the
"How this was computed" working is built server-side by the same function that
priced the run.

Everything under `/api/me/` is **ownership-scoped by the server**: `resolveSelf`
resolves the employee from the signed-in ACCOUNT, never from a request parameter,
so there is no id for the app to pass and none to tamper with. Adding My Payslips
therefore needed no server change — those routes were already inside the mobile
token's `/api/me/` window.

| Environment | Default address | Editable in app |
|---|---|---|
| Main HRIS | `http://192.168.137.1:5000` (the dev PC's hotspot, for now) | yes — Login › Advanced |
| Sandbox | `https://turbine-chamomile-financial.ngrok-free.dev` | yes |

On the Android emulator, the host PC is `10.0.2.2`: set Sandbox to `http://10.0.2.2:5001`
under Login › Advanced to hit a sandbox server running on the PC (debug builds only).

## Passwords

There is **no self-service change-password in the app**. A reset starts with HR on
the website: Employee → Account → **Reset password**, which has the server generate
a temporary password and show it once. HR hands it over; the employee signs in with
it (on either surface) and is then forced to choose their own before anything else
works — the server refuses every other route with `PASSWORD_CHANGE_REQUIRED` until
they do.

It is one `users.password_hash` behind both surfaces, so there is nothing to sync:
a password chosen on the phone works on the website immediately, and one chosen on
the website works on the phone. Offering a second, voluntary "change password" on
the phone would be a weaker door to the same credential, bypassing the handover the
flow is built around — so the app only points at the real route.

## The face check

Every punch is face-verified (2026-09-13). Tapping **Time In** or **Time Out** takes
a GPS fix, then opens the face check: the server issues a single-use nonce and a
randomized ordered liveness sequence (blink / turn head), the app runs exactly that
sequence, and the captured embedding is submitted with the punch. The server is
authoritative for all of it — anti-replay, challenge integrity, the liveness gate
and the 1:1 match. There is **no manual fallback**: a fallback one tap away would
make the biometric gate optional. An employee with no enrolled face is told so on
the home screen and cannot punch until HR enrols them on the website.

The embedding is produced by the **same `@vladmandic/human` build and the same model
weights the web client uses** — `assets/face/human.js` and `assets/face/models/` are
byte-for-byte copies of `client/node_modules/@vladmandic/human/dist/human.js` and
`client/public/models/`. That is not an optimisation, it is the requirement: a
different model means a different vector space, and every template already enrolled
from the website would stop matching. Everything that touches the embedding — the
Human config, the L2 normalisation, the eye-openness formula, the liveness
thresholds — is ported verbatim from `client/src/services/faceEngine.js` and
`client/src/utils/liveness.js` into `assets/face/capture.html`. **Change one and you
must change both.**

The capture runs in a WebView because that is the only way to run that exact
library. It is served from a loopback HTTP server inside the app
(`lib/features/face/face_asset_server.dart`) rather than `file://`, for two reasons:
`getUserMedia` needs a secure context, and Human fetches its weights (blocked from a
`file://` document unless the WebView is opened up, which is not a thing to do in an
app handling biometrics). Loopback is allowlisted in
`android/app/src/main/res/xml/network_security_config.xml`; without that entry the
page silently never loads. Nothing is fetched from the network — the weights ship in
the APK, which is also what RA 10173 wants (no third-party fetch of a biometric
model).

Camera permission is requested at the first capture, never at launch.

## Who sees what

| Login | Time Clock | Attendance | My Payslips |
|---|---|---|---|
| Employee (mobile switch on) | clock in / out | **Mine** — own DTR, month by month | own payslips |
| HR-type employee (`attendance:view`) | clock in / out | **Mine / Everyone** switch | own payslips |
| Super Admin or special account with `attendance:view` | "No employee record" | **Everyone** — the team DTR for a day | "No employee record" |

My Payslips is the phone's copy of the website's **My Payslips** — the same list,
the same detail (status, the four figures, the employee-share statutory
contributions, the itemised lines grouped by category) and the same *How this was
computed* working. It is read-only, and a payslip that is not yours is a 404 on
the server, so the app can never enumerate anybody else's.

"Everyone" is read-only and is the only console route a mobile token may reach
(`GET /api/attendance/calendar`, still behind the same permission and branch
scope as the website). Pick a day, search by name or code, page through a big
roster; each person shows their badge, punches, place labels and chips (late,
undertime, mobile app, out of range). No coordinates are shown on the phone.

Change the compiled defaults at build time:

```powershell
flutter build apk --release --dart-define=HRIS_MAIN_URL=https://hris.example.com --dart-define=HRIS_SANDBOX_URL=https://sandbox.example.com
```

Cleartext HTTP is allowed only for `192.168.137.1`, for `127.0.0.1`/`localhost` (the
face capture's in-app asset server, which never leaves the device) and for `10.0.2.2`
in debug builds; a production host must be HTTPS.

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

Navigation is the website's **sidebar**, behind the top bar's menu button:
`lib/features/shell/app_drawer.dart` draws `Sidebar.module.css` — the brand block
over its hairline, the signed-in account, uppercase section labels, and the active
item in primary-soft with primary text (`.itemActive`). It replaced the three
bottom tabs when My Payslips made a fourth destination: a tab bar stops scaling
there, and the sidebar is the shape this product already has in the browser.

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
             location (gate + fixes), time (Manila time, server clock),
             format (money, the web's formatMoney/exactRate)
  features/  auth (login, forced password change), consent, time_clock, attendance,
             payslips, face (the capture screen + its loopback asset server),
             settings, shell (the sidebar + the location gate)
  shared/    theme, widgets
assets/face/ the capture page, human.js and the model weights (~15 MB, copied
             from the web client — see 'The face check')
test/        unit + widget tests (flutter test)
```
