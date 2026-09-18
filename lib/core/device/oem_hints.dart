/// Extra, brand-specific background settings. These brands stop background
/// apps on top of stock Android's battery optimisation, and no API reports
/// those switches — so the best the app can do is name them.
///
/// `onAppInfoPage` says WHERE the steps live: on the HRIS entry of the phone's
/// app list (Xiaomi, OPPO/realme, Samsung — the page `openAppSettings` opens),
/// or somewhere else in the phone's Settings / a maker's own app (vivo's
/// i Manager, HUAWEI's Battery › App launch, Infinix's Phone Master) that no
/// button can reach. An "Open app settings" button is only offered for the
/// first kind: on a HONOR it landed on a page with none of the steps on it,
/// which read as a wrong turn (user, 2026-09-17).
class OemHint {
  final String brand;
  final List<String> steps;
  final bool onAppInfoPage;

  const OemHint(this.brand, this.steps, {this.onAppInfoPage = false});

  /// Where the reader should look, in plain words.
  String get where => onAppInfoPage ? "on the HRIS page of your phone's app settings" : "in your phone's Settings";
}

/// The hint for a `Build.MANUFACTURER`, or null for phones that follow stock
/// Android (Google Pixel, Motorola, Nokia…). Matched loosely: some brands
/// report a long company name ("INFINIX MOBILITY LIMITED").
OemHint? oemBatteryHint(String manufacturer) {
  final m = manufacturer.toLowerCase().trim();
  if (m.isEmpty) return null;
  bool any(List<String> names) => names.any(m.contains);

  if (any(const ['xiaomi', 'redmi', 'poco'])) {
    return const OemHint('Xiaomi / Redmi / POCO', [
      'Autostart: turn it ON.',
      'Battery saver: choose "No restrictions".',
    ], onAppInfoPage: true);
  }
  if (any(const ['oppo', 'realme', 'oneplus'])) {
    return const OemHint('OPPO / realme / OnePlus', [
      'Battery usage: turn ON "Allow background activity".',
      'Also turn ON "Allow auto launch" if you see it.',
    ], onAppInfoPage: true);
  }
  if (any(const ['vivo', 'iqoo'])) {
    return const OemHint('vivo', [
      'Battery › Background power consumption: allow HRIS.',
      'Also turn ON Auto-start for HRIS if you see it (i Manager › App manager).',
    ]);
  }
  if (any(const ['samsung'])) {
    return const OemHint('Samsung', [
      'Battery: choose "Unrestricted".',
      'Then in Settings › Battery › Background usage limits, HRIS must NOT be in "Sleeping apps".',
    ], onAppInfoPage: true);
  }
  if (any(const ['huawei', 'honor'])) {
    return const OemHint('HUAWEI / HONOR', [
      'Battery › App launch › HRIS: turn OFF "Manage automatically".',
      'Then turn ON Auto-launch, Secondary launch and Run in background.',
    ]);
  }
  if (any(const ['infinix', 'tecno', 'itel'])) {
    return const OemHint('Infinix / TECNO / itel', [
      'Phone Master (or Settings › App management) › Auto-start: allow HRIS.',
      'Lock HRIS in the recent-apps screen so it is not cleared.',
    ]);
  }
  return null;
}

/// Where to allow EXACT ALARMS — the clock reminders' "Alarms & reminders"
/// switch, which only Android 12 leaves to the user (13+ grants it to this app
/// at install) and which no dialog can set (2026-09-18: the button that tried
/// did nothing).
///
/// ACCURACY OVER DETAIL. A menu path is given only where it is the same on
/// every phone of that brand running Android 12 — stock Android and Samsung
/// One UI 4. The other skins move the page between versions, so for them the
/// step is Settings' own SEARCH, which finds it on every skin; a guessed path
/// that turns out wrong is worse than none. Never null: every phone gets the
/// search step at least.
OemHint oemExactAlarmHint(String manufacturer) {
  final m = manufacturer.toLowerCase().trim();
  bool any(List<String> names) => names.any(m.contains);
  const search =
      'Open Settings, tap the search bar at the top, type "alarms" and open "Alarms & reminders" (on some phones "Alarms and reminders" or "Set alarms and reminders").';
  const allow = 'Find HRIS in the list and turn the switch ON.';

  if (any(const ['samsung'])) {
    return const OemHint('Samsung', [
      'Settings › Apps › tap ⋮ (top right) › Special access › Alarms and reminders.',
      allow,
      'Can\'t find it? $search',
    ]);
  }
  if (any(const ['google', 'motorola', 'nokia', 'hmd'])) {
    return const OemHint('this', [
      'Settings › Apps › Special app access › Alarms & reminders.',
      allow,
      'Can\'t find it? $search',
    ]);
  }
  final brand = any(const ['xiaomi', 'redmi', 'poco'])
      ? 'Xiaomi / Redmi / POCO'
      : any(const ['oppo', 'realme', 'oneplus'])
          ? 'OPPO / realme / OnePlus'
          : any(const ['vivo', 'iqoo'])
              ? 'vivo'
              : any(const ['huawei', 'honor'])
                  ? 'HUAWEI / HONOR'
                  : any(const ['infinix', 'tecno', 'itel'])
                      ? 'Infinix / TECNO / itel'
                      : 'this';
  return OemHint(brand, const [search, allow]);
}
