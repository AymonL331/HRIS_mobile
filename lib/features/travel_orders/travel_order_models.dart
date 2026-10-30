import '../../shared/widgets/status_badge.dart';

/// Proof photos required per pinned stop (travelOrder.service TO_MIN_PHOTOS).
const toMinPhotos = 3;

/// TO_STATUS_LABELS / TO_STATUS_TONE (web constants/travelOrderEnums.js).
String toStatusLabel(String status) => switch (status) {
      'pending' => 'Pending Approval',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => status,
    };

StatusTone toStatusTone(String status) => switch (status) {
      'pending' => StatusTone.warning,
      'approved' || 'completed' => StatusTone.success,
      'rejected' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

/// TO_DAY_TYPE_LABELS, in the web's order.
const toDayTypes = <String, String>{
  'whole_day': 'Whole Day',
  'half_day_am': 'Half Day (AM)',
  'half_day_pm': 'Half Day (PM)',
};

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
String _date(Object? v) => _s(v).length >= 10 ? _s(v).substring(0, 10) : _s(v);

/// One row of My Travel Orders (GET /api/me/travel-orders).
class TravelOrderSummary {
  final int id;
  final String toNumber;
  final String purpose;
  final String dateFrom;
  final String dateTo;
  final String status;

  const TravelOrderSummary({
    required this.id,
    required this.toNumber,
    required this.purpose,
    required this.dateFrom,
    required this.dateTo,
    required this.status,
  });

  factory TravelOrderSummary.fromJson(Map<String, dynamic> j) => TravelOrderSummary(
        id: _i(j['id']),
        toNumber: _s(j['to_number']),
        purpose: _s(j['purpose']),
        dateFrom: _date(j['date_from']),
        dateTo: _date(j['date_to']),
        status: _s(j['status']),
      );
}

/// A stop of my trip. The server strips the arrival GPS from my view (RA 10173);
/// only whether and when I checked in comes back.
class TravelStop {
  final int id;
  final String name;
  final bool arrived;
  final DateTime? arrivedAt;

  const TravelStop({required this.id, required this.name, required this.arrived, this.arrivedAt});

  factory TravelStop.fromJson(Map<String, dynamic> j) => TravelStop(
        id: _i(j['id']),
        name: _s(j['name']),
        arrived: j['arrived'] == true || j['arrived_at'] != null,
        arrivedAt: j['arrived_at'] == null ? null : DateTime.tryParse('${j['arrived_at']}'.replaceFirst(' ', 'T'))?.toUtc(),
      );
}

class TravelPhoto {
  final int id;
  final int? destId;
  final String fileUrl;

  const TravelPhoto({required this.id, this.destId, required this.fileUrl});

  factory TravelPhoto.fromJson(Map<String, dynamic> j) => TravelPhoto(
        id: _i(j['id']),
        destId: j['dest_id'] == null ? null : _i(j['dest_id']),
        fileUrl: _s(j['file_url']),
      );
}

/// One of my travel orders with its stops, proof and completion checklist
/// (GET /api/me/travel-orders/:id) — the web track panel's data.
class TravelOrderDetail {
  final int id;
  final String toNumber;
  final String purpose;
  final String dateFrom;
  final String dateTo;
  final String dayType;
  final String status;
  final String completionRemarks;
  final List<TravelStop> stops;
  final List<TravelPhoto> photos;
  final int? nextDestId;
  final bool completionReady;
  final List<String> completionReasons;
  final String? completedBy;

  const TravelOrderDetail({
    required this.id,
    required this.toNumber,
    required this.purpose,
    required this.dateFrom,
    required this.dateTo,
    required this.dayType,
    required this.status,
    required this.completionRemarks,
    required this.stops,
    required this.photos,
    required this.nextDestId,
    required this.completionReady,
    required this.completionReasons,
    this.completedBy,
  });

  factory TravelOrderDetail.fromJson(Map<String, dynamic> j) {
    final completion = (j['completion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final arrivals = (j['arrivals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final completedBy = (j['completed_by'] as Map?)?['name'];
    return TravelOrderDetail(
      id: _i(j['id']),
      toNumber: _s(j['to_number']),
      purpose: _s(j['purpose']),
      dateFrom: _date(j['date_from']),
      dateTo: _date(j['date_to']),
      dayType: _s(j['day_type']),
      status: _s(j['status']),
      completionRemarks: _s(j['completion_remarks']),
      stops: ((j['destinations'] as List?) ?? const []).whereType<Map>().map((m) => TravelStop.fromJson(m.cast())).toList(),
      photos: ((j['photos'] as List?) ?? const []).whereType<Map>().map((m) => TravelPhoto.fromJson(m.cast())).toList(),
      nextDestId: arrivals['next_dest_id'] == null ? null : _i(arrivals['next_dest_id']),
      completionReady: completion['ready'] == true,
      completionReasons: ((completion['reasons'] as List?) ?? const []).map((e) => '$e').toList(),
      completedBy: completedBy == null ? null : '$completedBy',
    );
  }

  List<TravelPhoto> photosFor(int stopId) => photos.where((p) => p.destId == stopId).toList();

  /// Once the remarks are saved on an approved order, my submission is frozen
  /// pending approval (the server's addProof lock): no more photos, no edits.
  bool get remarksLocked => status == 'approved' && completionRemarks.trim().isNotEmpty;
}

/// May I file (GET /api/me/travel-order-readiness): a Travel Order day is
/// clocked by face, so filing needs an approved face first.
class TravelReadiness {
  final bool ready;
  final String profilePhoto; // approved | pending | missing
  final String face; // enrolled | pending | rejected | none
  final String? faceReason;

  const TravelReadiness({required this.ready, required this.profilePhoto, required this.face, this.faceReason});

  factory TravelReadiness.fromJson(Map<String, dynamic> j) => TravelReadiness(
        ready: j['ready'] == true,
        profilePhoto: _s(j['profile_photo']),
        face: _s(j['face']),
        faceReason: j['face_reason'] == null ? null : '${j['face_reason']}',
      );
}
