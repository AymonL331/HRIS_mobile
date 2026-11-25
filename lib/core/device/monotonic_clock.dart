import 'package:flutter/services.dart';

/// A reading of the phone's RUNNING clock (time since it started), which the
/// user cannot change, plus which start this is. Offline clock-in (2026-11-24)
/// keeps the last server time beside one of these, so a punch made with no
/// signal knows when it happened even if the phone's own clock was set by hand.
class MonotonicReading {
  final int elapsedMs;

  /// Android's boot counter; null where the phone does not report it. Two
  /// readings with different counts belong to different starts and cannot be
  /// compared.
  final int? bootCount;

  const MonotonicReading({required this.elapsedMs, required this.bootCount});
}

abstract class MonotonicClock {
  /// Null when the phone cannot say (then only the GPS time can vouch for a punch).
  Future<MonotonicReading?> read();
}

class PlatformMonotonicClock implements MonotonicClock {
  static const _channel = MethodChannel('hris/phone_state');

  const PlatformMonotonicClock();

  @override
  Future<MonotonicReading?> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('clock');
      final ms = m?['elapsedMs'];
      if (ms is! int) return null;
      final boot = m?['bootCount'];
      return MonotonicReading(elapsedMs: ms, bootCount: boot is int ? boot : null);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
