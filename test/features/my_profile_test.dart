import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/my_profile/my_profile_api.dart';
import 'package:hris_mobile/features/my_profile/my_profile_screen.dart';
import 'package:hris_mobile/features/my_profile/web_format.dart';

class FakeMyProfileApi implements MyProfileApi {
  Map<String, dynamic> profileJson = {};
  Map<String, dynamic> sectionsJson = {};
  bool failProfile = false;
  bool failSections = false;

  @override
  Future<Map<String, dynamic>> profile() async {
    if (failProfile) throw Exception('boom');
    return profileJson;
  }

  @override
  Future<Map<String, dynamic>> sections() async {
    if (failSections) throw Exception('boom');
    return sectionsJson;
  }
}

Map<String, dynamic> profile() => {
      'id': 29,
      'employee_code': 'PROLSCHO2020001',
      'id_card_no': '2020001',
      'first_name': 'Grace',
      'middle_name': 'M',
      'last_name': 'Jurban',
      'suffix': null,
      'status': 'active',
      'employment_status': 'probationary',
      'company_name': 'PROLSC',
      'branch_name': 'Head Office',
      'department_name': 'Finance',
      'designation_name': 'Accounting Staff',
      'reporting_to': {'id': 31, 'employee_code': 'PROLSCHO2020002', 'first_name': 'Neil', 'last_name': 'Malla'},
      'employment_type': 'full_time',
      'work_arrangement': 'office',
      'joining_date': '2026-10-01',
      'end_of_contract': null,
      'compensation': {
        'basic_salary': 15100,
        'salary_type': 'monthly',
        'work_days_per_year': 313,
        'daily_rate': 578.91,
        'source': {'basic_salary': 'employee', 'salary_type': 'branch', 'work_days_per_year': 'default'},
      },
      'date_of_birth': '1999-05-02',
      'age': 27,
      'gender': 'female',
      'civil_status': 'others',
      'civil_status_other': 'Engaged',
      'email': 'grace@example.test',
      'phone_country_code': '+63',
      'phone_number': '9171234567',
      'sss_no': '34-1234567-8',
      'account': {
        'username': 'grace',
        'email': 'grace@example.test',
        'data_access_level': 'self',
        'status': 'active',
        'last_login_at': '2026-11-23T07:05:00.000Z',
      },
      'biometric': {'enrolled': false},
    };

Map<String, dynamic> sections() => {
      'work_history': [
        {'id': 1, 'company_name': 'Acme Corp', 'date_from': '2020-01-01', 'date_to': '2022-12-31', 'position_title': 'Clerk'},
      ],
      'education': [],
      'family_members': [
        {'id': 3, 'relation': 'mother', 'name': 'Maria Jurban'},
      ],
      'background_disclosures': {'allergies': 'Peanuts', 'pending_legal_case_flag': 0, 'has_existing_loans': 1},
      'references': [],
    };

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> openTab(WidgetTester tester, String key) async {
  final tab = find.byKey(Key('section_tab_$key'));
  if (tab.hitTestable().evaluate().isEmpty) await tester.scrollUntilVisible(tab, -300, scrollable: find.byType(Scrollable).first);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header + Employment tab with compensation, as on the web', (tester) async {
    final api = FakeMyProfileApi()
      ..profileJson = profile()
      ..sectionsJson = sections();
    await tester.pumpWidget(host(MyProfileScreen(api: api, baseUrl: 'http://x')));
    await tester.pumpAndSettle();

    expect(find.text('Your personal and employment record.'), findsOneWidget);
    expect(find.text('Grace M Jurban'), findsOneWidget);
    expect(find.text('PROLSCHO2020001'), findsOneWidget);
    expect(find.text('ID card 2020001'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Probationary'), findsOneWidget);
    expect(find.text('Employment & Organization'), findsOneWidget);
    expect(find.text('Neil Malla (PROLSCHO2020002)'), findsOneWidget);
    expect(find.text('Full Time'), findsOneWidget);
    expect(find.text('Oct 1, 2026'), findsOneWidget);
    // No Profile Photo tab without the grant.
    expect(find.byKey(const Key('section_tab_photo')), findsNothing);
    await tester.scrollUntilVisible(find.text('Compensation'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('₱15,100.00'), findsOneWidget);
    expect(find.textContaining('per month'), findsOneWidget);
    expect(find.textContaining('branch default'), findsOneWidget);
    expect(find.textContaining('company default'), findsOneWidget);
    expect(find.textContaining('basic × 12 ÷ 313'), findsOneWidget);
  });

  testWidgets('Personal, Government IDs, Account tabs', (tester) async {
    final api = FakeMyProfileApi()
      ..profileJson = profile()
      ..sectionsJson = sections();
    await tester.pumpWidget(host(MyProfileScreen(api: api, baseUrl: 'http://x')));
    await tester.pumpAndSettle();

    await openTab(tester, 'personal');
    expect(find.text('Engaged'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('May 2, 1999'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('+63 9171234567'), 300, scrollable: find.byType(Scrollable).first);

    await openTab(tester, 'government');
    expect(find.text('Government IDs'), findsWidgets);
    expect(find.text('34-1234567-8'), findsOneWidget);

    await openTab(tester, 'account');
    expect(find.text('Active login'), findsOneWidget);
    expect(find.text('Self-service'), findsOneWidget);
    expect(find.text(WebFormat.dateTime('2026-11-23T07:05:00.000Z')), findsOneWidget);
    expect(find.text('Nov 23, 2026, 3:05 PM'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Not enrolled'), 300, scrollable: find.byType(Scrollable).first);
  });

  testWidgets('Work & Education and Family & References from the sections read', (tester) async {
    final api = FakeMyProfileApi()
      ..profileJson = profile()
      ..sectionsJson = sections();
    await tester.pumpWidget(host(MyProfileScreen(api: api, baseUrl: 'http://x')));
    await tester.pumpAndSettle();

    await openTab(tester, 'work_education');
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Jan 1, 2020 – Dec 31, 2022'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No education details recorded.'), 300, scrollable: find.byType(Scrollable).first);

    await openTab(tester, 'family_references');
    expect(find.text('Mother'), findsOneWidget);
    expect(find.text('Peanuts'), findsOneWidget);
    expect(find.text('No'), findsOneWidget); // pending legal case 0
    expect(find.text('Yes'), findsOneWidget); // existing loans 1
    await tester.scrollUntilVisible(find.text('No references recorded.'), 300, scrollable: find.byType(Scrollable).first);
  });

  testWidgets('profile error → Try again; sections error stays in its tab', (tester) async {
    final api = FakeMyProfileApi()
      ..failProfile = true
      ..failSections = true;
    await tester.pumpWidget(host(MyProfileScreen(api: api, baseUrl: 'http://x')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your profile"), findsOneWidget);

    api
      ..failProfile = false
      ..profileJson = profile();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Employment & Organization'), findsOneWidget);
    await openTab(tester, 'work_education');
    expect(find.text("Couldn't load the profile sections"), findsOneWidget);
  });

  testWidgets('does not load while hidden', (tester) async {
    var calls = 0;
    final api = _CountingApi(() => calls++);
    await tester.pumpWidget(host(MyProfileScreen(api: api, baseUrl: 'http://x', active: false)));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}

class _CountingApi implements MyProfileApi {
  final VoidCallback onCall;

  _CountingApi(this.onCall);

  @override
  Future<Map<String, dynamic>> profile() async {
    onCall();
    return profile_();
  }

  @override
  Future<Map<String, dynamic>> sections() async => const {};
}

Map<String, dynamic> profile_() => profile();
