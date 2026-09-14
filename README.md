# HRIS Mobile

The employee self-service app for the HRIS. Branch employees sign in with the same
credentials as the website, clock in / out from their own phone, read their own
DTR and read their own payslips. **Location is mandatory, precise and always-on**:
the app does not run unless the phone's location service is on and HRIS is granted
"Allow all the time" with "Use precise location" — "While using the app", "Only
this time" and "Approximate" all block it. Every punch takes a fresh GPS fix that
the server checks against the branch worksite. **Face recognition is mandatory
too** — see below.

Only accounts HR has switched on (**Employee profile › Account › Mobile app**)
can sign in. Turning the switch off signs the phone out on its next request.

## What it talks to

The same Node/Express API as the web app — no direct database access. It uses the
mobile-only endpoints added by migrations 057/058 (`/api/me/mobile-clock`,
`/api/me/mobile-clock/status`) plus `/api/auth/*`, `/api/me/mobile-location-consent`
(the app's OWN RA 10173 consent — migration 059, separate from the web field
clock's `/api/me/location-consent`, because the app requires always-on precise
location),
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

## Location: always + precise

The app refuses to run unless location is granted **"Allow all the time"** with
**precise** accuracy and the device's location service is on (2026-09-14). The
decision is one pure function, `decideGate` in
`lib/core/location/location_gate_service.dart`, so it reads as a truth table:
only `always` + precise (or `unknown`, which is pre-Android-12) passes.

### The phone-setup wizard

Anything short of that shows the **setup wizard** (`lib/features/setup/`) in place of
the app — one step per screen, "Step n of 5", each **explaining what is about to
appear before Android shows it**, with a drawing of that Android screen marking the
choice to tap and striking out the wrong ones:

| Step | Shown when | The button does |
|---|---|---|
| 1 Turn on location | location service off | opens location settings |
| 2 Allow location access | undecided / "Don't allow" | raises the first dialog — *keep Precise, tap While using the app **or** Only this time* (both land on step 3, which replaces either with Allow all the time; only Don't allow is struck out) |
| 3 Allow all the time | while-in-use, Approximate, or blocked for good | opens the Location-permission page (App info when Android won't route there) |
| 4 Allow notifications | Android 13+, not granted | the notification dialog (skippable) |
| 5 Run in the background | battery optimisation on | the "always run in background?" dialog + a brand hint for Xiaomi/OPPO/vivo/Samsung/… (skippable) |

Why (user, 2026-09-14): the old gate raised Android's dialog the moment the employee
signed in, with no guidance, and then chained the "all the time" request — which on
Android 11+ throws the user into Settings with no instruction; the explanation only
appeared after they pressed Back. **Nothing prompts on its own any more**: the mount
and every resume only observe (`LocationGateService.check()`); a dialog or Settings
page appears only from the button under its explanation (`requestForeground()`,
`requestBackground()`). The truth table from verdict to step is `nextSetupStep` in
`setup_step.dart`. Location steps cannot be skipped; a skipped optional step is
remembered (`setup.skipped` in SharedPreferences).

**Back** (the arrow, or the phone's back gesture) re-shows the previous step to
re-read — it never undoes anything, because the step is decided by what the phone
has granted. A re-read step says it is already done and offers only **Next**; no
dialog or Settings page opens from it, and real progress (a resume after granting)
ends the re-read. The first step has no Back, and there the gesture leaves the app
as before.

The drawings are Flutter widgets, not screenshots: the real screens differ by Android
version and brand, while the *words* on them do not.

Two Android facts shape this, and neither is negotiable:

- **The Precise/Approximate toggle cannot be removed** from the system dialog.
- **"Allow all the time" can never appear in that first dialog** on Android 11+.
  Background location is only grantable from the app's Settings page, so the
  blocked screen — not the permission request — is what actually gets people
  there.

**A trap for anyone touching this:** now that `ACCESS_BACKGROUND_LOCATION` is in
the manifest, `Geolocator.requestPermission()` appends it to the same
`requestPermissions()` call whenever the current status is already
`whileInUse` — and **Android 11+ silently ignores a request mixing foreground and
background, granting neither, with no dialog**. So it is only ever called from
`denied`, and the background ask goes through `permission_handler` alone. Do not
add a second `Geolocator.requestPermission()` call anywhere.

The gate re-checks on every app resume, and a check **never** raises a dialog.
Returning from Settings is itself a resume, so a prompting resume-check would bounce
the user straight back out in a loop. Every permission request is timed out (an
empty `grantResults` leaves geolocator's future hanging forever), and
`deniedForever` — which `checkPermission()` can never report — is remembered once a
request learns it.

## Work-hours location tracking (1.5.0)

From an employee's clock-in until their clock-out the app records where they are,
even with the screen off or the app swiped away, and HR reads the trail on the
website (server migration 060). Outside a shift nothing is recorded.

- **The server decides.** Every status load (and so every punch) calls
  `TrackingService.sync(status.tracking)`: the service runs while the server says the
  employee's open shift is active, and stops otherwise. The sampling policy (25 m /
  30 s / 5-min heartbeat / 16 h cap) comes from that same block.
- **The service** (`lib/features/tracking/tracking_task_handler.dart`) runs in
  `flutter_foreground_task`'s own engine behind a notification ("HRIS is recording
  your work location"): a position stream + heartbeat fixes → a `sqflite` queue →
  `POST /api/me/tracking/pings` every 2 min or 20 points, with backoff while offline.
  Location switched off, permission removed and a restart after a kill are recorded
  as events so the trail explains its own gaps. It stops itself when an upload says
  the shift closed, the session ended (queue kept) or consent was withdrawn (queue
  cleared), or at 16 h.
- **What survives what:** swipe-away (`stopWithTask=false`), a kill (auto-restart →
  `resumed_after_kill`), a reboot (`autoRunOnBoot`), offline stretches (the queue). A
  real sign-out or an environment switch stops it; an offline cold start that only
  shows the login screen does not.
- **The uploader's rules** (`ping_uploader.dart`, unit-tested): delete only after a
  2xx; network/5xx/ngrok page = retry later; 401 / access off = stop, keep the queue;
  consent withdrawn = stop, clear the queue; 404 = drop that shift; 422 envelope =
  drop the batch so it can never jam the queue. One shift per batch, oldest first.
- **On the Time Clock** a card says whether recording is on (last point, points
  waiting), or that the shift is open but this phone is not recording, with Restart.

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
manager, install, open, then grant Location as **Precise** → **Allow all the time**.
Android will not offer "Allow all the time" in the first dialog (it cannot, on
Android 11+) — the app then shows a screen naming the exact taps: **Permissions ›
Location › Allow all the time**, with **Use precise location** on. Expect to walk
the first few employees through that second step.
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
