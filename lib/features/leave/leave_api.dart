import '../../core/auth/session_controller.dart';
import 'leave_models.dart';

/// My Leave — the web's meService leave calls, all under the mobile token's
/// `/api/me/` window and self-scoped on the server (employee_id is forced to the
/// signed-in employee; another employee's request is a 404).
abstract final class LeaveEndpoints {
  static const types = '/api/me/leave/types';
  static const balances = '/api/me/leave/balances';
  static const requests = '/api/me/leave/requests';
  static String cancel(int id) => '/api/me/leave/requests/$id/cancel';
}

abstract class LeaveApi {
  /// My requests, newest first (useMyLeave: page, limit 20, sort date_from desc).
  Future<LeaveRequestPage> listRequests({int page = 1});

  /// My current balances.
  Future<List<LeaveBalance>> balances();

  /// Active leave types for the picker (status active, limit 100, by name).
  Future<List<LeaveType>> types();

  /// File a request: { leave_type_id, date_from, date_to, day_part, reason? }.
  Future<void> submit(Map<String, dynamic> payload);

  Future<void> cancel(int id);
}

class MobileLeaveApi implements LeaveApi {
  final SessionController session;

  const MobileLeaveApi(this.session);

  List<Map<String, dynamic>> _items(dynamic d) =>
      (((d as Map<String, dynamic>?)?['items'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();

  @override
  Future<LeaveRequestPage> listRequests({int page = 1}) => session.guard(() => session.client.get(
        LeaveEndpoints.requests,
        query: {'page': '$page', 'limit': '20', 'sort': 'date_from', 'order': 'desc'},
        parse: (d) => LeaveRequestPage.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<List<LeaveBalance>> balances() => session.guard(() => session.client.get(
        LeaveEndpoints.balances,
        parse: (d) => _items(d).map(LeaveBalance.fromJson).toList(),
      ));

  @override
  Future<List<LeaveType>> types() => session.guard(() => session.client.get(
        LeaveEndpoints.types,
        query: {'status': 'active', 'limit': '100', 'sort': 'name', 'order': 'asc'},
        parse: (d) => _items(d).map(LeaveType.fromJson).toList(),
      ));

  @override
  Future<void> submit(Map<String, dynamic> payload) =>
      session.guard(() => session.client.post<void>(LeaveEndpoints.requests, body: payload, parse: (_) {}));

  @override
  Future<void> cancel(int id) =>
      session.guard(() => session.client.post<void>(LeaveEndpoints.cancel(id), parse: (_) {}));
}
