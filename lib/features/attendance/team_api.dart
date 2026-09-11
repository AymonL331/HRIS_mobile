import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import 'team_models.dart';

/// The team DTR: every employee this login may see, for ONE date.
abstract class TeamAttendanceApi {
  Future<TeamDayPage> day({required String date, String search = '', int page = 1});
}

class MobileTeamAttendanceApi implements TeamAttendanceApi {
  static const pageSize = 100; // the server's cap for this list

  final SessionController session;

  const MobileTeamAttendanceApi(this.session);

  @override
  Future<TeamDayPage> day({required String date, String search = '', int page = 1}) {
    return session.guard(() => session.client.get(
          Endpoints.teamCalendar,
          query: {
            'date_from': date,
            'date_to': date,
            'page': '$page',
            'limit': '$pageSize',
            if (search.trim().isNotEmpty) 'search': search.trim(),
          },
          parse: (d) => TeamDayPage.fromJson(date, d as Map<String, dynamic>),
        ));
  }
}
