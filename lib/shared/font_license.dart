import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled IBM Plex licence (SIL Open Font License 1.1) to the app's
/// licences page — the OFL asks that it travel with the font files. Lazy: the
/// asset is only read when someone opens that page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['IBM Plex Sans', 'IBM Plex Mono'], text);
  });
}
