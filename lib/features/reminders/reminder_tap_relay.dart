import 'package:flutter/foundation.dart';

/// Carries the payload of a tapped reminder notification to whoever can act on
/// it. The tap can land before the shell exists (the notification launched the
/// app) or while it is showing any page — so the value is held until the shell
/// consumes it, rather than pushed at a widget that may not be there yet.
class ReminderTapRelay extends ValueNotifier<String?> {
  ReminderTapRelay() : super(null);

  void consume() => value = null;
}
