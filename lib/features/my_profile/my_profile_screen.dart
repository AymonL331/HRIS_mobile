import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/status_badge.dart';
import '../profile_photo/profile_photo_api.dart';
import '../profile_photo/profile_photo_screen.dart';
import 'detail_widgets.dart';
import 'employee_enums.dart';
import 'my_profile_api.dart';
import 'section_tabs.dart';
import 'viewable_photo_avatar.dart';
import 'web_format.dart';

/// MY PROFILE — the web My Profile (pages/employee/MyProfilePage.jsx) on the
/// phone: my own record, read-only, sliced by the same section tabs as the web
/// (Employment · Personal · Government IDs · Work & Education · Family &
/// References · Account, + Profile Photo with `profile_photo:create`). Every
/// value is DB-backed via GET /api/me/profile and /api/me/profile-sections.
class MyProfileScreen extends StatefulWidget {
  final MyProfileApi api;

  /// The environment's base URL — the photo path is relative to it.
  final String baseUrl;

  /// The login holds `profile_photo:create` (the web's `can('profile_photo','create')`).
  final bool canSendPhoto;

  /// For the Profile Photo tab (the app's own photo screen). No tab without it.
  final ProfilePhotoApi? photoApi;
  final ValueChanged<String?>? onPhotoChanged;

  /// Whether this page is the one showing: the record loads on first open.
  final bool active;

  const MyProfileScreen({
    super.key,
    required this.api,
    required this.baseUrl,
    this.canSendPhoto = false,
    this.photoApi,
    this.onPhotoChanged,
    this.active = true,
  });

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

const _tabs = [
  SectionTab('employment', 'Employment'),
  SectionTab('personal', 'Personal'),
  SectionTab('government', 'Government IDs'),
  SectionTab('work_education', 'Work & Education'),
  SectionTab('family_references', 'Family & References'),
  SectionTab('account', 'Account'),
];
const _photoTab = SectionTab('photo', 'Profile Photo');

enum _Load { idle, loading, ready, error }

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _profile;
  _Load _profileState = _Load.idle;
  Map<String, dynamic>? _sections;
  _Load _sectionsState = _Load.idle;
  String _tab = 'employment';

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadAll();
  }

  @override
  void didUpdateWidget(MyProfileScreen old) {
    super.didUpdateWidget(old);
    // The web page reloads each time it is opened; so does this one (the
    // record already shown stays on screen while the new read lands).
    if (widget.active && !old.active) _loadAll();
  }

  void _loadAll() {
    _loadProfile();
    _loadSections();
  }

  Future<void> _loadProfile() async {
    setState(() => _profileState = _Load.loading);
    try {
      final p = await widget.api.profile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _profileState = _Load.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _profileState = _Load.error);
    }
  }

  Future<void> _loadSections() async {
    setState(() => _sectionsState = _Load.loading);
    try {
      final s = await widget.api.sections();
      if (!mounted) return;
      setState(() {
        _sections = s;
        _sectionsState = _Load.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _sectionsState = _Load.error);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadProfile(), _loadSections()]);
  }

  bool get _hasPhotoTab => widget.canSendPhoto && widget.photoApi != null;

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final subtitle = Padding(
      padding: const EdgeInsets.only(bottom: HrisSpace.s4),
      child: Text('Your personal and employment record.', style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted)),
    );

    if (_profileState == _Load.idle || (_profileState == _Load.loading && _profile == null)) {
      return ListView(
        padding: _pad,
        children: [subtitle, if (_profileState == _Load.loading) const LoadingBlock(semanticsLabel: 'Loading your profile')],
      );
    }
    if (_profileState == _Load.error || _profile == null) {
      return ListView(
        padding: _pad,
        children: [
          subtitle,
          StatePanel(
            error: true,
            title: "Couldn't load your profile",
            message: 'Please try again.',
            action: OutlinedButton(onPressed: _loadProfile, child: const Text('Try again')),
          ),
        ],
      );
    }

    final e = _profile!;
    final tabs = _hasPhotoTab ? [..._tabs, _photoTab] : _tabs;
    final head = <Widget>[
      subtitle,
      _IdentityHeader(employee: e, baseUrl: widget.baseUrl),
      const SizedBox(height: HrisSpace.s5),
      SectionTabs(tabs: tabs, activeKey: _tab, onChange: (k) => setState(() => _tab = k), label: 'My profile sections'),
      const SizedBox(height: HrisSpace.s4),
    ];

    if (_tab == 'photo' && _hasPhotoTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ...head,
              Text('Profile Photo', style: TextStyle(fontSize: HrisType.md, height: 24 / 16, fontWeight: HrisType.semibold, color: t.text)),
              Text(
                "Change your photo with this device's camera. HR reviews it before it replaces the current one, and compares your face enrollment against it.",
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
              ),
            ]),
          ),
          Expanded(
            child: ProfilePhotoScreen(
              api: widget.photoApi!,
              baseUrl: widget.baseUrl,
              canSend: widget.canSendPhoto,
              onPhotoChanged: widget.onPhotoChanged,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pad,
        children: [...head, ..._tabBody(e)],
      ),
    );
  }

  static const _pad = EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6);

  List<Widget> _tabBody(Map<String, dynamic> e) {
    switch (_tab) {
      case 'employment':
        final manager = asJsonMap(e['reporting_to']);
        final managerText = manager == null
            ? ''
            : [manager['first_name'], manager['last_name']].where((v) => v != null && '$v'.isNotEmpty).join(' ') +
                (manager['employee_code'] != null && '${manager['employee_code']}'.isNotEmpty ? ' (${manager['employee_code']})' : '');
        return [
          DetailSection(
            title: 'Employment & Organization',
            description: 'Where you sit in the company, and your employment terms.',
            children: [
              DetailField('Company', webText(e['company_name'])),
              DetailField('Branch', webText(e['branch_name'])),
              DetailField('Department', webText(e['department_name'])),
              DetailField('Designation', webText(e['designation_name'])),
              DetailField('Reports to', managerText),
              DetailField('Employment type', labelFor(employmentTypeLabels, e['employment_type'])),
              DetailField('Work arrangement', labelFor(workArrangementLabels, e['work_arrangement'])),
              DetailField('Joining date', WebFormat.date(e['joining_date'])),
              DetailField('End of contract', WebFormat.date(e['end_of_contract'])),
              DetailField('Work assignment', webText(e['work_assignment'])),
              DetailField('Work schedule', webText(e['work_schedule'])),
            ],
          ),
          if (asJsonMap(e['compensation']) != null) _CompensationSection(asJsonMap(e['compensation'])!),
        ];
      case 'personal':
        final civil = e['civil_status'] == 'others' && '${e['civil_status_other'] ?? ''}'.isNotEmpty
            ? '${e['civil_status_other']}'
            : labelFor(civilStatusLabels, e['civil_status']);
        final phone = '${e['phone_number'] ?? ''}'.isEmpty
            ? ''
            : [e['phone_country_code'], e['phone_number']].where((v) => v != null && '$v'.isNotEmpty).join(' ');
        return [
          DetailSection(title: 'Personal', description: 'Your identity and personal background.', children: [
            DetailField('First name', webText(e['first_name'])),
            DetailField('Middle name', webText(e['middle_name'])),
            DetailField('Last name', webText(e['last_name'])),
            DetailField('Suffix', webText(e['suffix'])),
            DetailField('Nickname', webText(e['nickname'])),
            DetailField('Date of birth', WebFormat.date(e['date_of_birth'])),
            DetailField('Age', webText(e['age'])),
            DetailField('Gender', labelFor(genderLabels, e['gender'])),
            DetailField('Civil status', civil),
            DetailField('Nationality', webText(e['nationality'])),
            DetailField('Citizenship', webText(e['citizenship'])),
            DetailField('Religion', webText(e['religion'])),
            DetailField('Place of birth', webText(e['place_of_birth'])),
          ]),
          DetailSection(title: 'Contact & Address', description: 'How to reach you.', children: [
            DetailField('Email', webText(e['email'])),
            DetailField('Mobile', phone),
            DetailField('Landline', webText(e['landline_number'])),
            DetailField('Present address', webText(e['present_address'])),
            DetailField('Provincial address', webText(e['provincial_address'])),
          ]),
          DetailSection(title: 'Emergency Contact', description: 'Who we contact in an emergency.', children: [
            DetailField('Name', webText(e['emergency_contact_name'])),
            DetailField('Contact number', webText(e['emergency_contact_number'])),
          ]),
        ];
      case 'government':
        return [
          DetailSection(
            title: 'Government IDs',
            description: 'Your statutory identifiers — sensitive personal information (RA 10173).',
            children: [
              DetailField('SSS', webText(e['sss_no'])),
              DetailField('PhilHealth', webText(e['philhealth_no'])),
              DetailField('Pag-IBIG', webText(e['pagibig_no'])),
              DetailField('TIN', webText(e['tin_no'])),
              DetailField('Payroll bank account', webText(e['payroll_bank_account_number'])),
              DetailField('Bank account name', webText(e['payroll_bank_account_name'])),
              DetailField('Bank account channel', webText(e['payroll_bank_channel'])),
            ],
          ),
        ];
      case 'work_education':
        return _sectionsPanel(() {
          final s = _sections!;
          return [
            DetailSection(title: 'Work History', description: 'Previous employers from the application form.', children: [
              DetailRowsTable(
                rows: _rows(s['work_history']),
                emptyMessage: 'No work history recorded.',
                columns: [
                  RowsColumn('Company', (r) => webText(r['company_name'])),
                  RowsColumn(
                    'Inclusive dates',
                    (r) => '${r['inclusive_dates'] ?? ''}'.isNotEmpty
                        ? '${r['inclusive_dates']}'
                        : [WebFormat.date(r['date_from']), WebFormat.date(r['date_to'])].where((v) => v.isNotEmpty).join(' – '),
                  ),
                  RowsColumn('Position / Title', (r) => webText(r['position_title'])),
                  RowsColumn('Last salary', (r) => webText(r['last_salary'])),
                  RowsColumn('Reason for leaving', (r) => webText(r['reason_for_leaving']), long: true),
                ],
              ),
            ]),
            DetailSection(title: 'Education Details', description: 'Educational attainment per level.', children: [
              DetailRowsTable(
                rows: _rows(s['education']),
                emptyMessage: 'No education details recorded.',
                columns: [
                  RowsColumn('Level', (r) => labelFor(educationLevelLabels, r['level'])),
                  RowsColumn('Name of school / address', (r) => webText(r['school_name_address']), long: true),
                  RowsColumn('Degree / course', (r) => webText(r['degree_course'])),
                  RowsColumn('Year graduated', (r) => webText(r['year_graduated'])),
                ],
              ),
            ]),
          ];
        });
      case 'family_references':
        return _sectionsPanel(() {
          final s = _sections!;
          final d = asJsonMap(s['background_disclosures']);
          return [
            DetailSection(title: 'Family Data', description: 'Father, mother, spouse, siblings, and children.', children: [
              DetailRowsTable(
                rows: _rows(s['family_members']),
                emptyMessage: 'No family members recorded.',
                columns: [
                  RowsColumn('Relation', (r) => labelFor(familyRelationLabels, r['relation'])),
                  RowsColumn('Name', (r) => webText(r['name'])),
                  RowsColumn('Date of birth', (r) => WebFormat.date(r['date_of_birth'])),
                  RowsColumn('Occupation', (r) => webText(r['occupation'])),
                  RowsColumn('Home address & contact no.', (r) => webText(r['home_address_contact']), long: true),
                ],
              ),
            ]),
            DetailSection(
              title: 'Background Disclosures',
              description: 'Health, legal, and loan disclosures — sensitive personal information (RA 10173).',
              children: d == null
                  ? const [DetailField('Status', MutedValue('No disclosures recorded'))]
                  : [
                      for (final (field, label) in _disclosureLabels) DetailField(label, webText(d[field])),
                      DetailField('Pending civil / criminal case', _yesNo(d['pending_legal_case_flag'])),
                      DetailField('Nature of the pending case', webText(d['pending_legal_case_nature'])),
                      DetailField('Willing to take different store assignments', _yesNo(d['willing_store_assignments'])),
                      DetailField('Existing loans', _yesNo(d['has_existing_loans'])),
                      DetailField('SSS loan', _yesNo(d['loan_sss'])),
                      DetailField('Pag-IBIG loan', _yesNo(d['loan_pagibig'])),
                      DetailField('Other loans', webText(d['loan_others'])),
                    ],
            ),
            DetailSection(title: 'Professional References', description: 'References from the application form.', children: [
              DetailRowsTable(
                rows: _rows(s['references']),
                emptyMessage: 'No references recorded.',
                columns: [
                  RowsColumn('Name', (r) => webText(r['name'])),
                  RowsColumn('Relationship', (r) => webText(r['relationship'])),
                  RowsColumn('Occupation', (r) => webText(r['occupation'])),
                  RowsColumn('Address / tel no.', (r) => webText(r['address_tel_no']), long: true),
                ],
              ),
            ]),
          ];
        });
      case 'account':
        final account = asJsonMap(e['account']);
        final bio = asJsonMap(e['biometric']) ?? const {'enrolled': false};
        return [
          DetailSection(
            title: 'Account & Access',
            description: 'Your self-service login.',
            children: account == null
                ? const [DetailField('Status', MutedValue('No login account on record'))]
                : [
                    const DetailField('Status', StatusBadge('Active login', tone: StatusTone.success)),
                    DetailField('Username', webText(account['username'])),
                    DetailField('Sign-in email', webText(account['email'])),
                    DetailField('Access level', labelFor(dataAccessLabels, account['data_access_level'])),
                    DetailField('Account status', labelFor(statusLabels, account['status'])),
                    DetailField(
                      'Last sign-in',
                      account['last_login_at'] != null ? WebFormat.dateTime(account['last_login_at']) : 'Never',
                    ),
                  ],
          ),
          DetailSection(
            title: 'Biometric Enrollment',
            description: 'Your face-recognition timekeeping enrollment status.',
            children: bio['enrolled'] == true
                ? [
                    const DetailField('Status', StatusBadge('Enrolled', tone: StatusTone.success)),
                    DetailField('Consent', bio['consent_given'] == true ? 'Given' : 'Not recorded'),
                    DetailField('Consent recorded', bio['consent_at'] != null ? WebFormat.dateTime(bio['consent_at']) : ''),
                    DetailField('Enrolled on', bio['enrolled_at'] != null ? WebFormat.dateTime(bio['enrolled_at']) : ''),
                  ]
                : const [DetailField('Status', MutedValue('Not enrolled'))],
          ),
        ];
    }
    return const [];
  }

  /// The web SectionsPanel: its own loading / error state (the sections load
  /// from their own endpoint, independent of the employee row).
  List<Widget> _sectionsPanel(List<Widget> Function() ready) {
    if (_sectionsState == _Load.ready && _sections != null) return ready();
    if (_sectionsState == _Load.error) {
      return [
        StatePanel(
          error: true,
          title: "Couldn't load the profile sections",
          message: 'Please try again.',
          action: OutlinedButton(onPressed: _loadSections, child: const Text('Try again')),
        ),
      ];
    }
    return const [LoadingBlock(semanticsLabel: 'Loading profile sections')];
  }

  static List<Map<String, dynamic>> _rows(Object? v) =>
      v is List ? v.map(asJsonMap).whereType<Map<String, dynamic>>().toList() : const [];

  /// TINYINT NULL questionnaire flag: null = never answered, 1 = Yes, 0 = No.
  static String _yesNo(Object? v) {
    if (v == null || v == '') return '';
    final n = num.tryParse('$v') ?? (v == true ? 1 : 0);
    return n != 0 ? 'Yes' : 'No';
  }
}

const _disclosureLabels = [
  ('congenital_defect', 'Congenital / hereditary defect or ailment'),
  ('occupational_disease', 'Occupational disease / illness / accident'),
  ('neuro_psychiatric_treatment', 'Neurological / psychiatric treatment'),
  ('communicable_disease', 'Communicable disease'),
  ('allergies', 'Allergies'),
  ('administrative_case', 'Administrative case / dismissal for just cause'),
  ('fraternity_membership', 'Fraternity / employee group membership'),
  ('disability', 'Physical or mental disability'),
  ('relatives_in_company', 'Relatives in this company or a competitor'),
];

/// The page's identity header: the clickable photo, the full name, the employee
/// code and ID card number in mono, the status + employment-status badges.
class _IdentityHeader extends StatelessWidget {
  final Map<String, dynamic> employee;
  final String baseUrl;

  const _IdentityHeader({required this.employee, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final e = employee;
    final fullName = [e['first_name'], e['middle_name'], e['last_name'], e['suffix']]
        .where((v) => v != null && '$v'.isNotEmpty)
        .join(' ');
    final code = TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.sm, height: 20 / 14, color: t.muted);
    final status = '${e['status'] ?? ''}';
    final emp = '${e['employment_status'] ?? ''}';
    return Row(
      children: [
        ViewablePhotoAvatar(
          firstName: '${e['first_name'] ?? ''}',
          lastName: '${e['last_name'] ?? ''}',
          imageUrl: e['profile_image_url'] as String?,
          baseUrl: baseUrl,
          title: fullName,
        ),
        const SizedBox(width: HrisSpace.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName.isEmpty ? 'Employee' : fullName,
                style: TextStyle(fontSize: HrisType.md, height: 24 / 16, fontWeight: HrisType.semibold, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s2),
              Wrap(
                spacing: HrisSpace.s3,
                runSpacing: HrisSpace.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${e['employee_code'] ?? ''}'.isEmpty ? '—' : '${e['employee_code']}', style: code),
                  if ('${e['id_card_no'] ?? ''}'.isNotEmpty) Text('ID card ${e['id_card_no']}', style: code),
                  StatusBadge(statusLabels[status] ?? (status.isEmpty ? '—' : status), tone: statusTone(status)),
                  StatusBadge(employmentStatusLabels[emp] ?? (emp.isEmpty ? '—' : emp), tone: employmentStatusTone(emp)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The web CompensationDetail (self): basic salary per unit, salary type, work
/// days / year — each marked when it comes from the branch / company default —
/// and the monthly earner's daily rate equivalent.
class _CompensationSection extends StatelessWidget {
  final Map<String, dynamic> c;

  const _CompensationSection(this.c);

  static const _per = {'monthly': 'per month', 'daily': 'per day', 'hourly': 'per hour'};
  static const _sourceNote = {'branch': 'branch default', 'default': 'company default'};

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final source = asJsonMap(c['source']) ?? const {};
    final type = '${c['salary_type'] ?? ''}';
    final per = _per[type] ?? '';
    final body = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    final quiet = TextStyle(fontSize: HrisType.xs, color: t.muted);
    TextSpan? note(String key) {
      final n = _sourceNote['${source[key]}'];
      return n == null ? null : TextSpan(text: ' · $n', style: quiet);
    }

    Widget rich(List<InlineSpan?> spans) => Text.rich(TextSpan(style: body, children: spans.whereType<InlineSpan>().toList()));
    final days = webText(c['work_days_per_year']);
    return DetailSection(
      title: 'Compensation',
      description: 'Your pay basis. Questions about it go to HR.',
      children: [
        DetailField(
          'Basic salary',
          c['basic_salary'] == null
              ? Text('Not set', style: body.copyWith(color: t.muted))
              : rich([
                  TextSpan(text: Money.format(c['basic_salary']), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  TextSpan(text: ' $per'),
                  note('basic_salary'),
                ]),
        ),
        DetailField('Salary type', rich([TextSpan(text: salaryTypeLabels[type] ?? type), note('salary_type')])),
        DetailField('Work days / year', rich([TextSpan(text: days), note('work_days_per_year')])),
        if (c['daily_rate'] != null && type == 'monthly')
          DetailField(
            'Daily rate equivalent',
            rich([
              TextSpan(text: Money.format(c['daily_rate'])),
              TextSpan(text: ' · basic × 12 ÷ $days', style: quiet),
            ]),
          ),
      ],
    );
  }
}
