import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled font licences (both SIL Open Font License 1.1) to the app's
/// licences page — the OFL asks that it travel with the font files. Lazy: the
/// assets are only read when someone opens that page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final plex = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['IBM Plex Mono'], plex);
    final instrument = await rootBundle.loadString('assets/fonts/OFL-InstrumentSans.txt');
    yield LicenseEntryWithLineBreaks(const ['Instrument Sans'], instrument);
  });
}
