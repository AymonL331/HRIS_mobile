import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/features/attendance/correction_form_screen.dart' show PickedProof;
import 'package:hris_mobile/features/travel_orders/travel_order_api.dart';
import 'package:hris_mobile/features/travel_orders/travel_order_detail_screen.dart';
import 'package:hris_mobile/features/travel_orders/travel_order_form_screen.dart';
import 'package:hris_mobile/features/travel_orders/travel_order_models.dart';
import 'package:hris_mobile/features/travel_orders/travel_orders_screen.dart';

import '../fakes/clock_fakes.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

class FakeTravelOrderApi implements TravelOrderApi {
  Map<String, dynamic> readinessJson = {'ready': true, 'profile_photo': 'approved', 'face': 'enrolled'};
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> detailJson = {};
  final calls = <String>[];
  final created = <Map<String, dynamic>>[];
  final proofs = <Map<String, dynamic>>[];

  @override
  Future<TravelReadiness> readiness() async => TravelReadiness.fromJson(readinessJson);

  @override
  Future<List<TravelOrderSummary>> list() async => rows.map(TravelOrderSummary.fromJson).toList();

  @override
  Future<TravelOrderDetail> detail(int id) async => TravelOrderDetail.fromJson(detailJson);

  @override
  Future<String> stageAttachment({required Uint8List bytes, required String mimeType, required String name}) async {
    calls.add('stage $mimeType $name');
    return '/uploads/travel-orders/authority.jpg';
  }

  @override
  Future<void> create(Map<String, dynamic> payload) async => created.add(payload);

  @override
  Future<void> arrive(int id, {required int destId, required double lat, required double lng}) async =>
      calls.add('arrive $id $destId $lat,$lng');

  @override
  Future<void> addProof(int id, {int? destId, List<PickedProof> photos = const [], String? completionRemarks}) async =>
      proofs.add({'dest': destId, 'photos': photos.length, 'remarks': completionRemarks});

  @override
  Future<void> cancel(int id) async => calls.add('cancel $id');
}

Map<String, dynamic> order({String status = 'approved', String remarks = '', List<Map<String, dynamic>>? stops, int? next = 11}) => {
      'id': 7,
      'to_number': 'TO-2026-0042',
      'purpose': 'Branch surprise visit',
      'date_from': '2026-10-30',
      'date_to': '2026-10-31',
      'day_type': 'whole_day',
      'status': status,
      'completion_remarks': remarks,
      'destinations': stops ??
          [
            {'id': 10, 'seq': 1, 'name': 'Daraga Branch', 'arrived': true, 'arrived_at': '2026-10-30T01:15:00.000Z'},
            {'id': 11, 'seq': 2, 'name': 'Legazpi Branch', 'arrived': false, 'arrived_at': null},
            {'id': 12, 'seq': 3, 'name': 'Tabaco Branch', 'arrived': false, 'arrived_at': null},
          ],
      'photos': [],
      'arrivals': {'required': 3, 'arrived': 1, 'next_dest_id': next, 'all_arrived': false},
      'completion': {
        'ready': false,
        'reasons': ['Stop 1 (Daraga Branch) needs 3 more photo(s) (0 of 3)', 'Completion remarks required'],
      },
      'completed_by': null,
    };

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // A tall phone, so a whole trip (three stops, remarks, checklist) is built at once.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 4000);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });
  tearDown(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.resetPhysicalSize());

  testWidgets('no approved face: the checklist shows instead of the File button', (tester) async {
    final api = FakeTravelOrderApi()..readinessJson = {'ready': false, 'profile_photo': 'approved', 'face': 'none'};
    await tester.pumpWidget(host(TravelOrdersScreen(api: api, fixes: FakeFixService(), baseUrl: 'https://x', onOpenTimeClock: () {})));
    await tester.pumpAndSettle();

    expect(find.text('File a Travel Order'), findsNothing);
    expect(find.text('Get ready for Travel Orders'), findsOneWidget);
    expect(find.text('Your profile photo is on file.'), findsOneWidget);
    expect(find.text('Open the Time Clock'), findsOneWidget);
  });

  testWidgets('my orders are listed with their status, and open the trip', (tester) async {
    final api = FakeTravelOrderApi()
      ..rows = [
        {'id': 7, 'to_number': 'TO-2026-0042', 'purpose': 'Branch surprise visit', 'date_from': '2026-10-30', 'date_to': '2026-10-31', 'status': 'approved'},
        {'id': 6, 'to_number': 'TO-2026-0041', 'purpose': 'Collection run', 'date_from': '2026-10-20', 'date_to': '2026-10-20', 'status': 'pending'},
      ]
      ..detailJson = order();
    await tester.pumpWidget(host(TravelOrdersScreen(api: api, fixes: FakeFixService(), baseUrl: 'https://x')));
    await tester.pumpAndSettle();

    expect(find.text('File a Travel Order'), findsOneWidget);
    expect(find.text('TO-2026-0042'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Pending Approval'), findsOneWidget);

    await tester.tap(find.text('Branch surprise visit'));
    await tester.pumpAndSettle();
    expect(find.text('Legazpi Branch'), findsOneWidget);
    expect(find.text('Check in here'), findsOneWidget);
  });

  testWidgets('filing: required fields are named, then the authority is staged and the order filed', (tester) async {
    final api = FakeTravelOrderApi();
    final fixes = FakeFixService();
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderFormScreen(
        api: api,
        fixes: fixes,
        picker: (source) async => PickedProof(bytes: jpeg, mimeType: 'image/jpeg', name: 'authority.jpg'),
      ),
    ));

    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the purpose.'), findsOneWidget);
    expect(find.text('Select a start date.'), findsOneWidget);
    expect(find.text('Add at least one destination.'), findsOneWidget);
    expect(find.text('Attach the approved travel authority (image).'), findsOneWidget);
    expect(api.created, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Purpose *'), 'Branch surprise visit');
    await tester.tap(find.text('Select a date').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Place name'), 'Daraga Branch');
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(fixes.acquired, 1);
    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(api.calls, ['stage image/jpeg authority.jpg']);
    expect(api.created, hasLength(1));
    final p = api.created.single;
    expect(p['purpose'], 'Branch surprise visit');
    expect(p['date_from'], p['date_to'], reason: 'a one-day trip unless the end is changed');
    expect(p['day_type'], 'whole_day');
    expect(p['attachment_url'], '/uploads/travel-orders/authority.jpg');
    expect(p['destinations'], [
      {'name': 'Daraga Branch', 'lat': 14.5515, 'lng': 121.0177},
    ]);
  });

  testWidgets('a stop without a pin is refused on the phone', (tester) async {
    final api = FakeTravelOrderApi();
    await tester.pumpWidget(MaterialApp(home: TravelOrderFormScreen(api: api, fixes: FakeFixService())));
    await tester.enterText(find.widgetWithText(TextField, 'Place name'), 'Daraga Branch');
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(find.text('Pin the location — tap Use my location, or type the coordinates.'), findsOneWidget);
  });

  testWidgets('approved trip: check in at the NEXT stop only, with a fresh GPS reading', (tester) async {
    final api = FakeTravelOrderApi()..detailJson = order();
    final fixes = FakeFixService();
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderDetailScreen(api: api, id: 7, fixes: fixes, baseUrl: 'https://x', photoPicker: (_) async => const []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Check in here'), findsOneWidget, reason: 'only stop 2 is next');
    expect(find.text('Check in to the earlier stops first.'), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget, reason: 'stop 1 is checked in');
    expect(find.textContaining('Completion remarks required'), findsOneWidget);

    await tester.tap(find.text('Check in here'));
    await tester.pumpAndSettle();
    expect(fixes.acquired, 1);
    expect(api.calls, ['arrive 7 11 14.5515,121.0177']);
    expect(find.text('Checked in at Legazpi Branch.'), findsOneWidget);
  });

  testWidgets('a mocked location is refused before anything is sent', (tester) async {
    final api = FakeTravelOrderApi()..detailJson = order();
    final fixes = FakeFixService()
      ..next = LocationFix(latitude: 14.5, longitude: 121.0, accuracyM: 5, isMocked: true, at: DateTime.now());
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderDetailScreen(api: api, id: 7, fixes: fixes, baseUrl: 'https://x', photoPicker: (_) async => const []),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in here'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.textContaining('mock location'), findsOneWidget);
  });

  testWidgets('proof photos go to their stop; remarks are saved on their own', (tester) async {
    final api = FakeTravelOrderApi()..detailJson = order();
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderDetailScreen(
        api: api,
        id: 7,
        fixes: FakeFixService(),
        baseUrl: 'https://x',
        photoPicker: (source) async => [
          for (var i = 0; i < 3; i++) PickedProof(bytes: jpeg, mimeType: 'image/jpeg', name: 'p$i.jpg'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(api.proofs, [
      {'dest': 10, 'photos': 3, 'remarks': null},
    ]);
    expect(find.text('3 photos uploaded.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Completion remarks'), 'Visited all three branches.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save remarks'));
    await tester.pumpAndSettle();
    expect(api.proofs.last, {'dest': null, 'photos': 0, 'remarks': 'Visited all three branches.'});
  });

  testWidgets('saved remarks lock the trip: no more photos, read-only remarks', (tester) async {
    final api = FakeTravelOrderApi()..detailJson = order(remarks: 'Done.');
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderDetailScreen(api: api, id: 7, fixes: FakeFixService(), baseUrl: 'https://x', photoPicker: (_) async => const []),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Add photos'), findsNothing);
    expect(find.textContaining('your trip is locked pending approval'), findsOneWidget);
  });

  testWidgets('a pending order can be cancelled, and has nothing to check in yet', (tester) async {
    final api = FakeTravelOrderApi()..detailJson = order(status: 'pending');
    await tester.pumpWidget(MaterialApp(
      home: TravelOrderDetailScreen(api: api, id: 7, fixes: FakeFixService(), baseUrl: 'https://x', photoPicker: (_) async => const []),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Check in here'), findsNothing);
    expect(find.textContaining('Waiting for approval'), findsOneWidget);

    await tester.tap(find.text('Cancel this Travel Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel it'));
    await tester.pumpAndSettle();
    expect(api.calls, ['cancel 7']);
  });

  test('detail keeps no arrival GPS and reads the checklist', () {
    final d = TravelOrderDetail.fromJson(order());
    expect(d.stops.first.arrived, isTrue);
    expect(d.nextDestId, 11);
    expect(d.completionReasons, hasLength(2));
    expect(toStatusLabel('pending'), 'Pending Approval');
  });
}
