/// The time the SERVER thinks it is, carried forward from the last response.
///
/// A punch is stamped by the server, so the clock on the home screen shows the
/// server's time — the phone's clock may be minutes off, and an employee who
/// sees 7:59 on the phone and gets a 8:03 punch would rightly complain.
class ServerClock {
  Duration _offset = Duration.zero;
  bool _synced = false;

  bool get synced => _synced;

  void sync(DateTime serverUtc) {
    _offset = serverUtc.toUtc().difference(DateTime.now().toUtc());
    _synced = true;
  }

  DateTime nowUtc() => DateTime.now().toUtc().add(_offset);
}
