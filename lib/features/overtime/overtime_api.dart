import 'dart:convert';

import '../../core/auth/session_controller.dart';
import '../attendance/correction_form_screen.dart' show PickedProof;
import 'overtime_models.dart';

/// My Overtime & Holiday Work — the web's meService overtime calls, all under
/// /api/me/ (inside the mobile token's window). employee_id is forced to the
/// signed-in employee on the server; nothing here sends it.
abstract class OvertimeApi {
  static const requestsPath = '/api/me/overtime-requests';
  static const windowPath = '/api/me/overtime-window';
  static const holidayFormPath = '/api/me/overtime/holiday-form';
  static const profilePath = '/api/me/profile';
  static String requirementsPath(int id) => '/api/me/overtime-requests/$id/requirements';
  static String accomplishmentPath(int dateId) => '/api/me/overtime-dates/$dateId/accomplishment';
  static String reportPath(int id) => '/api/me/overtime-requests/$id/report';

  /// My filings, newest first: page / limit 20 / sort date / order desc.
  Future<OvertimePage> list({int page = 1});

  /// Who I am, for the filing form (name, department, designation).
  Future<OvertimeIdentity> identity();

  /// `?hours=&dates=` — hours omitted when not > 0, dates omitted when empty.
  Future<OvertimeWindow> window({num? hours, List<String> dates = const []});

  /// Stage one approved form (JPG / PNG / PDF); returns its stored URL ('' on none).
  Future<String> stageForm(PickedProof file);

  /// File: {dates, ot_hours, purpose, attachment_url?, more_attachment_urls?}.
  Future<void> submit(Map<String, dynamic> payload);

  /// The form + remarks for a filing my admin SET for me (migration 122).
  Future<void> completeRequirements(int id, Map<String, dynamic> payload);

  /// {accomplishment_note?, photos?} for one approved date.
  Future<void> submitAccomplishment(int dateId, {String? note, List<PickedProof> photos = const []});

  Future<OvertimeReport> report(int id);
}

Map<String, String> _file(PickedProof p) => {'name': p.name, 'type': p.mimeType, 'data': base64Encode(p.bytes)};

class MobileOvertimeApi implements OvertimeApi {
  final SessionController session;

  const MobileOvertimeApi(this.session);

  @override
  Future<OvertimePage> list({int page = 1}) => session.guard(() => session.client.get(
        OvertimeApi.requestsPath,
        query: {'page': '$page', 'limit': '20', 'sort': 'date', 'order': 'desc'},
        parse: (d) => OvertimePage.fromJson(d as Map<String, dynamic>?),
      ));

  @override
  Future<OvertimeIdentity> identity() => session.guard(() => session.client.get(
        OvertimeApi.profilePath,
        parse: (d) => OvertimeIdentity.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<OvertimeWindow> window({num? hours, List<String> dates = const []}) => session.guard(() => session.client.get(
        OvertimeApi.windowPath,
        query: {
          if (hours != null && hours > 0) 'hours': numText(hours),
          if (dates.isNotEmpty) 'dates': dates.join(','),
        },
        parse: (d) => OvertimeWindow.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<String> stageForm(PickedProof file) => session.guard(() => session.client.post(
        OvertimeApi.holidayFormPath,
        body: {'file': _file(file)},
        parse: (d) => '${(d as Map<String, dynamic>?)?['url'] ?? ''}',
      ));

  @override
  Future<void> submit(Map<String, dynamic> payload) =>
      session.guard(() => session.client.post(OvertimeApi.requestsPath, body: payload));

  @override
  Future<void> completeRequirements(int id, Map<String, dynamic> payload) =>
      session.guard(() => session.client.post(OvertimeApi.requirementsPath(id), body: payload));

  @override
  Future<void> submitAccomplishment(int dateId, {String? note, List<PickedProof> photos = const []}) =>
      session.guard(() => session.client.post(
            OvertimeApi.accomplishmentPath(dateId),
            body: {
              // Omitted, not '', when there is none: an empty string would clear a note.
              'accomplishment_note': ?note,
              if (photos.isNotEmpty) 'photos': [for (final p in photos) _file(p)],
            },
          ));

  @override
  Future<OvertimeReport> report(int id) => session.guard(() => session.client.get(
        OvertimeApi.reportPath(id),
        parse: (d) => OvertimeReport.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));
}
