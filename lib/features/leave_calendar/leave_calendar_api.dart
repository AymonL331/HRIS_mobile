import '../../core/auth/session_controller.dart';
import 'leave_calendar_models.dart';

/// The leave calendar's PORTAL door (myLeaveCalendarService): the same read the
/// website's Leave Calendar makes, inside the mobile token's `/api/me/` window.
/// The branch the session was opened through decides who is visible — enforced
/// on the server, never here.
abstract final class LeaveCalendarEndpoints {
  static const calendar = '/api/me/leave-calendar';
  static const people = '/api/me/leave-calendar/people';
}

abstract class LeaveCalendarApi {
  /// { scope, from, to, branch_id?, employee_id? }.
  Future<LeaveCalendarData> get({
    required String scope,
    required String from,
    required String to,
    String branchId = '',
    String employeeId = '',
  });

  /// { scope, branch_id?, search? } — server-side search over a capped list.
  Future<CalendarPeople> people({required String scope, String branchId = '', String search = ''});
}

class MobileLeaveCalendarApi implements LeaveCalendarApi {
  final SessionController session;

  const MobileLeaveCalendarApi(this.session);

  @override
  Future<LeaveCalendarData> get({
    required String scope,
    required String from,
    required String to,
    String branchId = '',
    String employeeId = '',
  }) =>
      session.guard(() => session.client.get(
            LeaveCalendarEndpoints.calendar,
            query: {
              'scope': scope,
              'from': from,
              'to': to,
              if (branchId.isNotEmpty) 'branch_id': branchId,
              if (employeeId.isNotEmpty) 'employee_id': employeeId,
            },
            parse: (d) => LeaveCalendarData.fromJson((d as Map<String, dynamic>?) ?? const {}),
          ));

  @override
  Future<CalendarPeople> people({required String scope, String branchId = '', String search = ''}) =>
      session.guard(() => session.client.get(
            LeaveCalendarEndpoints.people,
            query: {
              'scope': scope,
              if (branchId.isNotEmpty) 'branch_id': branchId,
              if (search.isNotEmpty) 'search': search,
            },
            parse: (d) => CalendarPeople.fromJson((d as Map<String, dynamic>?) ?? const {}),
          ));
}
