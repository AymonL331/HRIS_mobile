import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import 'payslip_breakdown_models.dart';
import 'payslip_models.dart';

/// One page of my payslips, with the server's pagination block.
class PayslipPage {
  final List<PayslipSummary> items;
  final int page;
  final int totalPages;
  final int total;

  const PayslipPage({required this.items, required this.page, required this.totalPages, required this.total});
}

abstract class PayslipApi {
  /// My payslips, newest first. Ownership is forced on the server, so there is
  /// no employee id to send.
  Future<PayslipPage> list({required int page, int limit});

  /// One of MY payslips + its itemised lines. A payslip that isn't mine is a
  /// 404 on the server (no cross-employee enumeration), which surfaces here as
  /// an [ApiException] with status 404.
  Future<Payslip> detail(int id);

  /// The working behind one payslip.
  Future<PayslipBreakdown> breakdown(int id);

  /// Where the WEB print page for this payslip lives, and the session token it
  /// signs in with — the app shows that page for "Print payslip" (user
  /// 2026-10-23: the payslip exactly as the website shows it on a phone).
  Future<PayslipPrintTarget> printTarget(int id);
}

/// The web print page of one payslip + the token the web app reads from
/// `localStorage['hris_token']`. `?app=1` hides the web page's own toolbar.
class PayslipPrintTarget {
  final Uri url;
  final String? token;

  const PayslipPrintTarget({required this.url, required this.token});
}

class MobilePayslipApi implements PayslipApi {
  final SessionController session;

  const MobilePayslipApi(this.session);

  @override
  Future<PayslipPage> list({required int page, int limit = 20}) => session.guard(() => session.client.get(
        Endpoints.payslips,
        // The same sort the web's My Payslips page asks for, so the phone and
        // the browser put the same payslip at the top.
        query: {'page': '$page', 'limit': '$limit', 'sort': 'created_at', 'order': 'desc'},
        parse: (d) {
          final map = (d as Map<String, dynamic>?) ?? const {};
          final items = (map['items'] as List?) ?? const [];
          final pagination = (map['pagination'] as Map<String, dynamic>?) ?? const {};
          int at(String key, int fallback) {
            final v = pagination[key];
            return v is int ? v : int.tryParse('$v') ?? fallback;
          }

          return PayslipPage(
            items: items.whereType<Map<String, dynamic>>().map(PayslipSummary.fromJson).toList(growable: false),
            page: at('page', page),
            totalPages: at('totalPages', 1),
            total: at('total', 0),
          );
        },
      ));

  @override
  Future<Payslip> detail(int id) => session.guard(() => session.client.get(
        Endpoints.payslip(id),
        parse: (d) => Payslip.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<PayslipBreakdown> breakdown(int id) => session.guard(() => session.client.get(
        Endpoints.payslipBreakdown(id),
        parse: (d) => PayslipBreakdown.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<PayslipPrintTarget> printTarget(int id) async {
    final client = session.client;
    final base = client.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return PayslipPrintTarget(
      url: Uri.parse('$base/employee/payslips/$id/print?app=1'),
      token: await client.tokenProvider(),
    );
  }
}
