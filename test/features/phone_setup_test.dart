import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/core/device/phone_state_service.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/tracking/phone_setup.dart';

/// 2026-11-19 ("Phone was silent"): the clock-in check now also sees the
/// settings that let the phone stop ATLAS, "Fix it" goes to the exact switch,
/// and the readings are reported to HR (server migration 125).

class _Gate implements LocationGateService {
  GateVerdict verdict;
  int openedLocation = 0;
  _Gate([this.verdict = GateVerdict.ok]);
  @override
  Future<GateVerdict> check() async => verdict;
  @override
  Future<GateVerdict> requestForeground() async => verdict;
  @override
  Future<GateVerdict> requestBackground() async => verdict;
  @override
  Future<void> openLocationSettings() async => openedLocation += 1;
  @override
  Future<void> openAppSettings() async {}
}

class _Device implements DeviceReadinessService {
  DeviceReadiness state;
  final calls = <String>[];
  _Device([this.state = DeviceReadiness.ready]);
  @override
  Future<DeviceReadiness> check() async => state;
  @override
  Future<void> requestNotifications() async => calls.add('notifications');
  @override
  Future<void> requestBatteryExemption() async => calls.add('battery');
  @override
  Future<void> openAppSettings() async => calls.add('app');
  @override
  Future<Set<String>> skippedSteps() async => const {};
  @override
  Future<void> skipStep(String name) async {}
}

class _Phone implements PhoneStateService {
  PhoneState state;
  final calls = <String>[];
  _Phone([this.state = PhoneState.unknown]);
  @override
  Future<PhoneState> read() async => state;
  @override
  Future<void> openBatterySaver() async => calls.add('saver');
  @override
  Future<void> openDataSaver() async => calls.add('data');
  @override
  Future<bool> openAutostart() async {
    calls.add('autostart');
    return true;
  }
}

class _Api implements PhoneSettingsApi {
  final sent = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<void> send(Map<String, dynamic> body) async {
    if (fail) throw Exception('offline');
    sent.add(body);
  }
}

void main() {
  group('PhoneState', () {
    test('Battery Saver blocks location only in the screen-off-location modes', () {
      for (final m in [1, 2, 3]) {
        expect(PhoneState.blocksLocation(powerSaveOn: true, locationPowerSaveMode: m), isTrue, reason: 'mode $m');
      }
      expect(PhoneState.blocksLocation(powerSaveOn: true, locationPowerSaveMode: 0), isFalse);
      expect(PhoneState.blocksLocation(powerSaveOn: true, locationPowerSaveMode: 4), isFalse);
      expect(PhoneState.blocksLocation(powerSaveOn: false, locationPowerSaveMode: 2), isFalse);
      expect(PhoneState.blocksLocation(powerSaveOn: true, locationPowerSaveMode: null), isNull);
      expect(PhoneState.blocksLocation(powerSaveOn: null, locationPowerSaveMode: 2), isNull);
    });

    test('read from the Android channel; missing or odd values stay unknown', () {
      final s = PhoneState.fromChannel({
        'backgroundRestricted': true,
        'powerSaveOn': true,
        'locationPowerSaveMode': 1,
        'dataSaverOn': 'yes',
        'model': 'Redmi Note 13',
        'osVersion': '',
      });
      expect(s.backgroundRestricted, isTrue);
      expect(s.powerSaveBlocksLocation, isTrue);
      expect(s.dataSaverOn, isNull);
      expect(s.model, 'Redmi Note 13');
      expect(s.osVersion, isNull);
    });
  });

  group('clock-in check', () {
    Future<SetupProblem?> check(_Gate g, _Device d, [_Phone? p]) =>
        trackingReadinessProblem(gate: g, device: d, phone: p);

    test('everything fine -> null', () async {
      expect(await check(_Gate(), _Device(), _Phone()), isNull);
    });

    test('location first, each to its own fix', () async {
      expect((await check(_Gate(GateVerdict.serviceOff), _Device()))!.fix, SetupFix.locationSettings);
      expect((await check(_Gate(GateVerdict.backgroundDenied), _Device()))!.fix, SetupFix.appSettings);
    });

    test('battery saving -> Android\'s own dialog, with Autostart offered on a Xiaomi only', () async {
      const xiaomi = DeviceReadiness(notificationsGranted: true, batteryUnrestricted: false, manufacturer: 'xiaomi');
      final p = (await check(_Gate(), _Device(xiaomi)))!;
      expect(p.fix, SetupFix.batteryExemption);
      expect(p.offerAutostart, isTrue);
      const pixel = DeviceReadiness(notificationsGranted: true, batteryUnrestricted: false, manufacturer: 'google');
      expect((await check(_Gate(), _Device(pixel)))!.offerAutostart, isFalse);
      const samsung = DeviceReadiness(notificationsGranted: true, batteryUnrestricted: false, manufacturer: 'samsung');
      expect((await check(_Gate(), _Device(samsung)))!.offerAutostart, isFalse);
    });

    test('"Restricted" blocks with the app page; Battery Saver that kills location blocks with its own page', () async {
      final r = await check(_Gate(), _Device(), _Phone(const PhoneState(backgroundRestricted: true)));
      expect(r!.fix, SetupFix.appSettings);
      expect(r.message, contains('Restricted'));
      final s = await check(_Gate(), _Device(), _Phone(const PhoneState(powerSaveOn: true, powerSaveBlocksLocation: true)));
      expect(s!.fix, SetupFix.batterySaver);
      expect(s.message, contains('Battery Saver'));
    });

    test('Data Saver, Battery Saver that leaves location alone, and unknowns never block', () async {
      expect(await check(_Gate(), _Device(), _Phone(const PhoneState(dataSaverOn: true))), isNull);
      expect(await check(_Gate(), _Device(), _Phone(const PhoneState(powerSaveOn: true, powerSaveBlocksLocation: false))), isNull);
      expect(await check(_Gate(), _Device(), _Phone(const PhoneState(powerSaveOn: true))), isNull);
      expect(await check(_Gate(), _Device()), isNull);
    });
  });

  test('"Fix it" opens the right thing for each fix', () async {
    final g = _Gate();
    final d = _Device();
    final p = _Phone();
    await applySetupFix(SetupFix.locationSettings, gate: g, device: d, phone: p);
    await applySetupFix(SetupFix.batteryExemption, gate: g, device: d, phone: p);
    await applySetupFix(SetupFix.notifications, gate: g, device: d, phone: p);
    await applySetupFix(SetupFix.appSettings, gate: g, device: d, phone: p);
    await applySetupFix(SetupFix.batterySaver, gate: g, device: d, phone: p);
    expect(g.openedLocation, 1);
    expect(d.calls, ['battery', 'notifications', 'app']);
    expect(p.calls, ['saver']);
  });

  group('reporter', () {
    test('sends what the phone reads; the same settings are not re-sent within 30 min unless forced', () async {
      var now = DateTime(2026, 11, 19, 8);
      final api = _Api();
      final phone = _Phone(const PhoneState(powerSaveOn: true, powerSaveBlocksLocation: true, dataSaverOn: false, model: 'X', osVersion: '14'));
      final r = PhoneSettingsReporter(
        api: api,
        gate: _Gate(),
        device: _Device(const DeviceReadiness(notificationsGranted: true, batteryUnrestricted: false, manufacturer: 'xiaomi')),
        phone: phone,
        now: () => now,
      );
      await r.report();
      expect(api.sent, hasLength(1));
      expect(api.sent.single, {
        'location_ok': true,
        'notifications_allowed': true,
        'battery_unrestricted': false,
        'background_restricted': null,
        'power_saver_on': true,
        'power_saver_blocks_location': true,
        'data_saver_on': false,
        'manufacturer': 'xiaomi',
        'model': 'X',
        'os_version': '14',
      });
      await r.report();
      expect(api.sent, hasLength(1), reason: 'unchanged, too soon');
      await r.report(force: true);
      expect(api.sent, hasLength(2), reason: 'clock-in always sends');
      now = now.add(const Duration(minutes: 31));
      await r.report();
      expect(api.sent, hasLength(3), reason: 'unchanged but stale');
      phone.state = const PhoneState(powerSaveOn: false, powerSaveBlocksLocation: false, dataSaverOn: false, model: 'X', osVersion: '14');
      await r.report();
      expect(api.sent, hasLength(4), reason: 'changed: sent at once');
      expect(api.sent.last['power_saver_on'], isFalse);
    });

    test('a failed send never throws and is retried next time', () async {
      final api = _Api()..fail = true;
      final r = PhoneSettingsReporter(api: api, gate: _Gate(), device: _Device());
      await r.report();
      expect(api.sent, isEmpty);
      api.fail = false;
      await r.report();
      expect(api.sent, hasLength(1));
    });
  });
}
