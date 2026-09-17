import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/http/api_exception.dart';
import 'reminder_models.dart';
import 'reminder_notifier.dart';
import 'reminders_api.dart';

/// The bell's brain — the website's `useNotifications` hook, ported: a
/// newest-first page for the list + the unread count for the badge, a silent
/// background poll every [pollInterval] while the app is on screen, arrival
/// detection, and optimistic mark-read / acknowledge / remove that resync on
/// failure (the UI must never lie about read state).
///
/// Arrivals are handed to the [ReminderNotifier], the same door the alarm
/// callback uses — so a reminder that lands while the app is open makes the
/// same sound as one that lands while it is closed (user decision 2026-09-17),
/// and one that was already shown by the alarm is not shown again.
class NotificationsController extends ChangeNotifier with WidgetsBindingObserver {
  final NotificationsApi api;
  final ReminderNotifier? notifier;
  final Duration pollInterval;

  /// Whether to watch the app lifecycle (pause the poll in the background).
  /// Off in unit tests, which have no widgets binding.
  final bool observeLifecycle;

  static const pageLimit = 10;

  List<AppNotification> _items = const [];
  int _unreadCount = 0;
  bool _loading = false;
  String? _error;
  bool _started = false;
  bool _disposed = false;
  int _requestId = 0;
  Timer? _timer;

  /// Ids already reported. Seeded silently by the FIRST load so a cold start
  /// never announces the rows that were already sitting there.
  Set<int>? _seen;

  NotificationsController({
    required this.api,
    this.notifier,
    this.pollInterval = const Duration(seconds: 30),
    this.observeLifecycle = true,
  });

  List<AppNotification> get items => _items;
  int get unreadCount => _unreadCount;
  bool get loading => _loading;
  String? get error => _error;
  bool get started => _started;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Begin: the first load, then the poll. A login with no employee never
  /// starts (nothing to fetch, and `/api/me/*` would 404).
  void start() {
    if (_started || _disposed) return;
    _started = true;
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (pollInterval <= Duration.zero) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        unawaited(poll());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _timer?.cancel();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// The list and the badge count, fetched together. `Future.wait` rather than
  /// a record `.wait`, which would wrap a failure in a ParallelWaitError and
  /// hide the server's message.
  Future<(NotificationPage, int)> _fetch() async {
    final results = await Future.wait<Object>([api.list(limit: pageLimit), api.unreadCount()]);
    return (results[0] as NotificationPage, results[1] as int);
  }

  /// A manual load (mount, opening the list, a resync after a failed write).
  /// Never announces anything — it just re-baselines what has been seen.
  Future<void> load() async {
    final requestId = ++_requestId;
    _loading = true;
    _error = null;
    _notify();
    try {
      final (page, count) = await _fetch();
      if (requestId != _requestId) return;
      // The FIRST load is the baseline: what is already here is on the badge,
      // not news — so the background refresh must not announce it later either.
      if (_seen == null) {
        final notifier = this.notifier;
        if (notifier != null) {
          for (final n in page.items.where((n) => !n.isRead)) {
            unawaited(notifier.markShown(n));
          }
        }
      }
      _seen = page.items.map((n) => n.id).toSet();
      _items = page.items;
      _unreadCount = count;
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      _error = e.message;
    } catch (e) {
      if (requestId != _requestId) return;
      _error = 'Could not load notifications.';
    } finally {
      if (requestId == _requestId) {
        _loading = false;
        _notify();
      }
    }
  }

  /// The background refresh: no spinner, errors ignored (keep the last good
  /// list). Reports only UNREAD rows never seen before — the page is a fixed
  /// size, so an old row can slide back into view when a newer one is read.
  Future<void> poll() async {
    final requestId = ++_requestId;
    try {
      final (page, count) = await _fetch();
      if (requestId != _requestId || _disposed) return;
      final seen = _seen;
      if (seen == null) {
        _seen = page.items.map((n) => n.id).toSet();
      } else {
        final fresh = page.items.where((n) => !seen.contains(n.id) && !n.isRead).toList();
        for (final n in page.items) {
          seen.add(n.id);
        }
        final notifier = this.notifier;
        if (notifier != null) {
          for (final n in fresh) {
            unawaited(notifier.showIfNew(n));
          }
        }
      }
      _items = page.items;
      _unreadCount = count;
      _notify();
    } catch (_) {
      // Transient poll errors never disturb the list.
    }
  }

  AppNotification? _find(int id) {
    for (final n in _items) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _replace(int id, AppNotification Function(AppNotification) f) {
    _items = [for (final n in _items) n.id == id ? f(n) : n];
  }

  Future<void> markRead(int id) async {
    final target = _find(id);
    if (target == null) return;
    final wasUnread = !target.isRead;
    if (!wasUnread) return;
    _replace(id, (n) => n.copyWith(readAt: DateTime.now().toUtc()));
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    _notify();
    try {
      await api.markRead(id);
    } catch (_) {
      await load();
    }
  }

  Future<void> markAllRead() async {
    final stamp = DateTime.now().toUtc();
    _items = [for (final n in _items) n.isRead ? n : n.copyWith(readAt: stamp)];
    _unreadCount = 0;
    _notify();
    try {
      await api.markAllRead();
    } catch (_) {
      await load();
    }
  }

  /// ACKNOWLEDGE — a compliance record, so unlike mark-read it is NOT
  /// fire-and-forget: the future completes only once the server recorded it,
  /// and a failure resyncs and rethrows so the screen can say so. Acknowledging
  /// implies read (the server does the same), so the badge drops here too.
  Future<void> acknowledge(int id) async {
    final target = _find(id);
    if (target == null) return;
    final wasUnread = !target.isRead;
    final stamp = DateTime.now().toUtc();
    _replace(id, (n) => n.copyWith(readAt: n.readAt ?? stamp, acknowledgedAt: n.acknowledgedAt ?? stamp));
    if (wasUnread) _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    _notify();
    try {
      final updated = await api.acknowledge(id);
      _replace(id, (_) => updated);
      _notify();
    } catch (e) {
      await load();
      rethrow;
    }
  }

  /// REMOVE from my inbox. Optimistic; the seen set keeps the id on purpose so
  /// a re-baseline can never announce a row the employee deleted.
  Future<void> remove(int id) async {
    final target = _find(id);
    if (target == null) return;
    final wasUnread = !target.isRead;
    _items = [for (final n in _items) if (n.id != id) n];
    if (wasUnread) _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    _notify();
    try {
      await api.remove(id);
    } catch (e) {
      await load();
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started && observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
