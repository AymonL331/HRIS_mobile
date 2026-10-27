import 'dart:convert';
import 'dart:typed_data';

import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import 'attendance_models.dart';

abstract class AttendanceApi {
  /// Every day of one month, newest first. [upToDate] caps the window (the
  /// current month runs to today, not to its last day — future days are noise).
  Future<List<DtrDay>> month({required int year, required int month, required String upToDate});

  /// Totals for a period plus the month-by-month breakdown. Empty bounds = all time.
  Future<AttendanceSummary> summary({String? dateFrom, String? dateTo});

  /// My latest correction requests, newest date first.
  Future<List<CorrectionRequest>> corrections();

  /// Stage the proof photo; returns the stored URL the request then carries.
  Future<String> stageProof({required Uint8List bytes, required String mimeType, required String name});

  /// File the correction. [payload] is the web dialog's body: date, reason,
  /// proof_photo_url and the requested times in UTC ("YYYY-MM-DD HH:MM").
  Future<void> submitCorrection(Map<String, dynamic> payload);
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

  @override
  Future<AttendanceSummary> summary({String? dateFrom, String? dateTo}) => session.guard(() => session.client.get(
        Endpoints.attendanceSummary,
        // One page of months (the server caps a page at 100) — a year is 12.
        query: {
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          'page': '1',
          'limit': '100',
        },
        parse: (d) => AttendanceSummary.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<List<CorrectionRequest>> corrections() => session.guard(() => session.client.get(
        Endpoints.correctionRequests,
        query: {'limit': '20', 'sort': 'date', 'order': 'desc'},
        parse: (d) {
          final items = ((d as Map<String, dynamic>?)?['items'] as List?) ?? const [];
          return items.whereType<Map<String, dynamic>>().map(CorrectionRequest.fromJson).toList();
        },
      ));

  @override
  Future<String> stageProof({required Uint8List bytes, required String mimeType, required String name}) =>
      session.guard(() => session.client.post(
            Endpoints.correctionProof,
            body: {
              'file': {'name': name, 'type': mimeType, 'data': base64Encode(bytes)},
            },
            parse: (d) => '${(d as Map<String, dynamic>?)?['url'] ?? ''}',
          ));

  @override
  Future<void> submitCorrection(Map<String, dynamic> payload) =>
      session.guard(() => session.client.post(Endpoints.correctionSubmit, body: payload));
}
