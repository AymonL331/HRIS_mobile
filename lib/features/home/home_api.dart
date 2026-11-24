import '../../core/auth/session_controller.dart';
import 'home_models.dart';

/// Home — the web's GET /api/me/dashboard: my current-year leave balances,
/// latest payslip, pending request counts and the company's upcoming holidays,
/// every figure scoped to me on the server. Inside the mobile `/api/me/` window.
abstract class HomeApi {
  Future<MyDashboard> dashboard();
}

class MobileHomeApi implements HomeApi {
  static const dashboardPath = '/api/me/dashboard';

  final SessionController session;

  const MobileHomeApi(this.session);

  @override
  Future<MyDashboard> dashboard() => session.guard(() => session.client.get(
        dashboardPath,
        parse: (d) => MyDashboard.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));
}
