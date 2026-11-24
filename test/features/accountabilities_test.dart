import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/accountabilities/accountabilities_api.dart';
import 'package:hris_mobile/features/accountabilities/accountabilities_models.dart';
import 'package:hris_mobile/features/accountabilities/accountabilities_screen.dart';

// 1×1 transparent PNG.
final png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class FakeAccountabilitiesApi implements AccountabilitiesApi {
  Map<String, dynamic> json = {};
  ApiException? error;
  final photos = <String>[];

  @override
  Future<MyAccountabilities> listMine() async {
    if (error != null) throw error!;
    return MyAccountabilities.fromJson(json);
  }

  @override
  Future<Uint8List> photo(int itemId, String field) async {
    photos.add('$itemId/$field');
    return png;
  }
}

Map<String, dynamic> data() => {
      'sections': [
        {
          'id': 1,
          'name': 'Devices',
          'status': 'active',
          'fields': [
            {'key': 'serial_number', 'label': 'Serial number', 'type': 'text'},
            {'key': 'date_received', 'label': 'Date received', 'type': 'date'},
            {'key': 'photo', 'label': 'Photo', 'type': 'photo'},
            {'key': 'imei', 'label': 'IMEI', 'type': 'text'},
          ],
        },
        {
          'id': 2,
          'name': 'Accounts',
          'status': 'active',
          'fields': [
            {'key': 'username', 'label': 'Username', 'type': 'text'},
            {'key': 'password', 'label': 'Password', 'type': 'password'},
          ],
        },
      ],
      'items': [
        {
          'id': 10,
          'section_id': 1,
          'name': 'Laptop',
          'status': 'onboarding',
          'details': {'serial_number': 'SN-123', 'date_received': '2026-10-01'},
          'layout': {
            'labels': {'serial_number': 'Laptop serial'},
            'na': ['imei'],
            'extra': [
              {'key': 'x_charger', 'label': 'Charger', 'type': 'text'},
            ],
          },
          'photo_keys': ['photo'],
          'secret_keys': [],
          'updated_at': '2026-10-01T00:00:00.000Z',
        },
        {
          'id': 11,
          'section_id': 2,
          'name': 'Email',
          'status': 'onboarding',
          'details': {'username': 'grace@pro'},
          'layout': null,
          'photo_keys': [],
          'secret_keys': ['password'],
        },
        {
          'id': 12,
          'section_id': 1,
          'name': 'Old phone',
          'status': 'offboarding',
          'details': {},
          'layout': null,
          'returned_at': '2026-10-20',
          'return_condition': 'damaged',
          'return_notes': 'Cracked screen',
          'returned_by_username': 'hr.anne',
          'photo_keys': [],
          'secret_keys': [],
        },
      ],
      'counts': {'total': 3, 'onboarding': 2, 'offboarding': 1},
    };

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('With me: groups, sub lines, details open with photo and hidden password', (tester) async {
    final api = FakeAccountabilitiesApi()..json = data();
    await tester.pumpWidget(host(AccountabilitiesScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('What the company issued you'), findsOneWidget);
    expect(find.text('With me (2)'), findsOneWidget);
    expect(find.text('Returned (1)'), findsOneWidget);
    expect(find.text('DEVICES'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Date received: Oct 1, 2026'), findsOneWidget);
    expect(find.text('With the employee'), findsOneWidget); // Email has no date
    expect(find.text('Old phone'), findsNothing);

    await tester.tap(find.byKey(const Key('acc_item_10')));
    await tester.pumpAndSettle();
    expect(find.text('Laptop serial'), findsOneWidget);
    expect(find.text('SN-123'), findsOneWidget);
    expect(find.text('IMEI'), findsOneWidget);
    expect(find.text('Not applicable'), findsOneWidget);
    expect(find.text('Charger'), findsNothing); // extra with no value is not shown
    expect(api.photos, ['10/photo']);
    expect(find.byKey(const Key('acc_photo_10_photo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('acc_item_11')));
    await tester.pumpAndSettle();
    expect(find.text('●●●●●●●●'), findsOneWidget);
    expect(find.text('Show'), findsNothing);
  });

  testWidgets('Returned tab shows the return line', (tester) async {
    final api = FakeAccountabilitiesApi()..json = data();
    await tester.pumpWidget(host(AccountabilitiesScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('section_tab_offboarding')));
    await tester.pumpAndSettle();
    expect(find.text('Old phone'), findsOneWidget);
    expect(find.text('Returned Oct 20, 2026 · Damaged'), findsOneWidget);
    await tester.tap(find.byKey(const Key('acc_item_12')));
    await tester.pumpAndSettle();
    expect(find.text('None entered.'), findsOneWidget);
    expect(find.text('Damaged'), findsOneWidget);
    expect(find.text('· recorded by hr.anne'), findsOneWidget);
    expect(find.text('· Cracked screen'), findsOneWidget);
  });

  testWidgets('empty texts per tab', (tester) async {
    final api = FakeAccountabilitiesApi()
      ..json = {
        'sections': data()['sections'],
        'items': [],
        'counts': {'total': 0, 'onboarding': 0, 'offboarding': 0},
      };
    await tester.pumpWidget(host(AccountabilitiesScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is recorded as issued to you.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('section_tab_offboarding')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing returned yet.'), findsOneWidget);
  });

  testWidgets('error with Try again', (tester) async {
    final api = FakeAccountabilitiesApi()..error = const ApiException(status: 500, message: 'Nope');
    await tester.pumpWidget(host(AccountabilitiesScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your accountabilities"), findsOneWidget);
    api
      ..error = null
      ..json = data();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
  });

  test('effectiveFields relabels, flags N/A and appends extras', () {
    final s = AccSection.fromJson((data()['sections'] as List).first as Map<String, dynamic>);
    final f = effectiveFields(s, {
      'labels': {'serial_number': 'Laptop serial'},
      'na': ['imei'],
      'extra': [
        {'key': 'x_charger', 'label': 'Charger', 'type': 'text'},
      ],
    });
    expect(f.map((e) => e.label), ['Laptop serial', 'Date received', 'Photo', 'IMEI', 'Charger']);
    expect(f.firstWhere((e) => e.key == 'imei').na, isTrue);
  });
}
