import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import 'attendance_models.dart';

abstract class AttendanceApi {
  /// Every day of one month, newest first. [upToDate] caps the window (the
  /// current month runs to today, not to its last day — future days are noise).
  Future<List<DtrDay>> month({required int year, required int month, required String upToDate});
}

class MobileAttendanceApi implements AttendanceApi {
  final SessionController session;

  const MobileAttendanceApi(this.session);

  @override
  Future<List<DtrDay>> month({required int year, required int month, required String upToDate}) {
    final first = '$year-${month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final last = '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    final to = upToDate.compareTo(last) < 0 && upToDate.startsWith(first.substring(0, 7)) ? upToDate : last;
    return session.guard(() => session.client.get(
          Endpoints.attendanceCalendar,
          query: {'date_from': first, 'date_to': to, 'sort': 'date', 'order': 'desc', 'limit': '31', 'page': '1'},
          parse: (d) {
            final items = ((d as Map<String, dynamic>)['items'] as List?) ?? const [];
            return items.whereType<Map<String, dynamic>>().map(DtrDay.fromJson).toList();
          },
        ));
  }
}
