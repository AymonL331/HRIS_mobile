// LEAVE CALENDAR — the web's /api/me/leave-calendar payloads
// (services/leaveCalendar.service.js getCalendar / listPeople). The leave
// `reason` is never in the payload (RA 10173 sensitive data), so there is
// nothing to hide here: it was never fetched.

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
String _date(Object? v) {
  final s = v?.toString() ?? '';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

class CalendarLeave {
  final int id;
  final int employeeId;
  final String? employeeCode;
  final String employeeName;
  final String? branchName;
  final String? leaveTypeName;
  final String dateFrom;
  final String dateTo;
  final Object? days;
  final String status;
  final bool isSelf;

  const CalendarLeave({
    required this.id,
    required this.employeeId,
    this.employeeCode,
    required this.employeeName,
    this.branchName,
    this.leaveTypeName,
    required this.dateFrom,
    required this.dateTo,
    this.days,
    required this.status,
    this.isSelf = false,
  });

  factory CalendarLeave.fromJson(Map<String, dynamic> j) => CalendarLeave(
        id: _int(j['id']),
        employeeId: _int(j['employee_id']),
        employeeCode: j['employee_code'] as String?,
        employeeName: '${j['employee_name'] ?? ''}',
        branchName: j['branch_name'] as String?,
        leaveTypeName: j['leave_type_name'] as String?,
        dateFrom: _date(j['date_from']),
        dateTo: _date(j['date_to']),
        days: j['days'],
        status: '${j['status'] ?? ''}',
        isSelf: j['is_self'] == true,
      );
}

class CalendarHoliday {
  final int id;
  final String title;
  final String date;
  final String? type;
  final bool companyWide;
  final String? branchName;

  const CalendarHoliday({
    required this.id,
    required this.title,
    required this.date,
    this.type,
    this.companyWide = false,
    this.branchName,
  });

  factory CalendarHoliday.fromJson(Map<String, dynamic> j) => CalendarHoliday(
        id: _int(j['id']),
        title: '${j['title'] ?? ''}',
        date: _date(j['date']),
        type: j['type'] as String?,
        companyWide: j['company_wide'] == true,
        branchName: j['branch_name'] as String?,
      );

  /// LeaveDayPanel's type line.
  String get typeLabel => type == 'regular'
      ? 'Regular holiday'
      : type == 'special_non_working'
          ? 'Special (non-working)'
          : 'Special (working)';

  String get whereLabel => companyWide ? 'All branches' : (branchName ?? 'Branch holiday');
}

class BranchOption {
  final int id;
  final String name;

  const BranchOption(this.id, this.name);
}

class LeaveCalendarData {
  final List<CalendarLeave> leaves;
  final List<CalendarHoliday> holidays;
  final Map<String, bool> availableScopes;
  final List<BranchOption> availableBranches;
  final bool truncated;

  const LeaveCalendarData({
    this.leaves = const [],
    this.holidays = const [],
    this.availableScopes = const {'self': false, 'branch': false, 'all': true},
    this.availableBranches = const [],
    this.truncated = false,
  });

  /// useLeaveCalendar's EMPTY, so the first frame has the same defaults as the web.
  static const empty = LeaveCalendarData();

  factory LeaveCalendarData.fromJson(Map<String, dynamic> j) {
    final scopes = j['available_scopes'];
    return LeaveCalendarData(
      leaves: ((j['leaves'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(CalendarLeave.fromJson).toList(),
      holidays:
          ((j['holidays'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(CalendarHoliday.fromJson).toList(),
      availableScopes: scopes is Map
          ? {for (final k in const ['self', 'branch', 'all']) k: scopes[k] == true}
          : empty.availableScopes,
      availableBranches: ((j['available_branches'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((b) => BranchOption(_int(b['id']), '${b['name'] ?? ''}'))
          .toList(),
      truncated: j['truncated'] == true,
    );
  }
}

class CalendarPerson {
  final int id;
  final String? employeeCode;
  final String name;
  final String? branchName;

  const CalendarPerson({required this.id, this.employeeCode, required this.name, this.branchName});

  factory CalendarPerson.fromJson(Map<String, dynamic> j) => CalendarPerson(
        id: _int(j['id']),
        employeeCode: j['employee_code'] as String?,
        name: '${j['name'] ?? ''}',
        branchName: j['branch_name'] as String?,
      );

  /// The picker option: label = name (or code), hint = "code · branch".
  String get label => name.isNotEmpty ? name : (employeeCode ?? '');
  String get hint => [employeeCode, branchName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

class CalendarPeople {
  final List<CalendarPerson> items;
  final bool truncated;

  const CalendarPeople({this.items = const [], this.truncated = false});

  factory CalendarPeople.fromJson(Map<String, dynamic> j) => CalendarPeople(
        items: ((j['items'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(CalendarPerson.fromJson).toList(),
        truncated: j['truncated'] == true,
      );
}
