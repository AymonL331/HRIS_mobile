import 'dart:convert';
import 'dart:typed_data';

import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import '../attendance/correction_form_screen.dart' show PickedProof;
import 'travel_order_models.dart';

/// My Travel Orders — the web's /api/me/travel-orders* calls, self-scoped on the
/// server (employee_id is forced to the signed-in employee; my view never carries
/// the arrival GPS). Inside the mobile token's `/api/me/` window.
abstract class TravelOrderApi {
  Future<TravelReadiness> readiness();
  Future<List<TravelOrderSummary>> list();
  Future<TravelOrderDetail> detail(int id);

  /// Stage the approved travel authority image; returns its stored URL.
  Future<String> stageAttachment({required Uint8List bytes, required String mimeType, required String name});

  /// File the order: purpose, date_from, date_to, day_type, attachment_url and
  /// destinations [{name, lat, lng}] — the web dialog's body.
  Future<void> create(Map<String, dynamic> payload);

  /// Sequential GPS check-in at the next stop.
  Future<void> arrive(int id, {required int destId, required double lat, required double lng});

  /// Proof photos for a stop and/or the completion remarks (at least one).
  Future<void> addProof(int id, {int? destId, List<PickedProof> photos = const [], String? completionRemarks});

  Future<void> cancel(int id);
}

class MobileTravelOrderApi implements TravelOrderApi {
  final SessionController session;

  const MobileTravelOrderApi(this.session);

  @override
  Future<TravelReadiness> readiness() => session.guard(() => session.client.get(
        Endpoints.travelOrderReadiness,
        parse: (d) => TravelReadiness.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<List<TravelOrderSummary>> list() => session.guard(() => session.client.get(
        Endpoints.travelOrders,
        query: {'page': '1', 'limit': '50'},
        parse: (d) {
          final items = ((d as Map<String, dynamic>?)?['items'] as List?) ?? const [];
          return items.whereType<Map<String, dynamic>>().map(TravelOrderSummary.fromJson).toList();
        },
      ));

  @override
  Future<TravelOrderDetail> detail(int id) => session.guard(() => session.client.get(
        Endpoints.travelOrder(id),
        parse: (d) => TravelOrderDetail.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<String> stageAttachment({required Uint8List bytes, required String mimeType, required String name}) =>
      session.guard(() => session.client.post(
            Endpoints.travelOrderAttachment,
            body: {
              'file': {'name': name, 'type': mimeType, 'data': base64Encode(bytes)},
            },
            parse: (d) => '${(d as Map<String, dynamic>?)?['url'] ?? ''}',
          ));

  @override
  Future<void> create(Map<String, dynamic> payload) =>
      session.guard(() => session.client.post(Endpoints.travelOrders, body: payload));

  @override
  Future<void> arrive(int id, {required int destId, required double lat, required double lng}) =>
      session.guard(() => session.client.post(
            Endpoints.travelOrderArrive(id),
            body: {'dest_id': destId, 'lat': lat, 'lng': lng},
          ));

  @override
  Future<void> addProof(int id, {int? destId, List<PickedProof> photos = const [], String? completionRemarks}) =>
      session.guard(() => session.client.post(
            Endpoints.travelOrderProof(id),
            body: {
              'dest_id': ?destId,
              if (photos.isNotEmpty)
                'photos': [
                  for (final p in photos) {'name': p.name, 'type': p.mimeType, 'data': base64Encode(p.bytes)},
                ],
              'completion_remarks': ?completionRemarks,
            },
          ));

  @override
  Future<void> cancel(int id) => session.guard(() => session.client.post(Endpoints.travelOrderCancel(id)));
}
