/// The signed-in account as the server describes it (`data.user` on login,
/// `data` on `GET /api/auth/me`). Only the fields the app acts on are kept.
class User {
  final int id;
  final int tenantId;
  final int? employeeId;
  final String username;
  final String email;
  final String? roleName;
  final bool mustChangePassword;
  final bool mobileAccessEnabled;

  /// The role's grants as `module:action` strings, exactly as the server sends
  /// them. Used only to decide what to SHOW — the server's `authorize` is the
  /// real gate on every call. A Super Admin's list is empty (the role bypasses
  /// every gate by name), so the role name is checked alongside it.
  final List<String> permissions;

  static const superAdminRole = 'Super Admin';

  const User({
    required this.id,
    required this.tenantId,
    required this.employeeId,
    required this.username,
    required this.email,
    required this.roleName,
    required this.mustChangePassword,
    required this.mobileAccessEnabled,
    this.permissions = const [],
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: _int(j['id'])!,
        tenantId: _int(j['tenant_id']) ?? 0,
        employeeId: _int(j['employee_id']),
        username: (j['username'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        roleName: j['role_name'] as String?,
        mustChangePassword: _flag(j['must_change_password']),
        mobileAccessEnabled: _flag(j['mobile_access_enabled']),
        permissions: (j['permissions'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
      );

  bool get isSuperAdmin => roleName == superAdminRole;

  bool can(String permission) => isSuperAdmin || permissions.contains(permission);

  /// May this login open the team DTR ("Everyone" on the Attendance tab)? The
  /// same grant the web console's DTR needs; the server re-checks it.
  bool get canViewTeamAttendance => can('attendance:view');

  User copyWith({bool? mustChangePassword}) => User(
        id: id,
        tenantId: tenantId,
        employeeId: employeeId,
        username: username,
        email: email,
        roleName: roleName,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
        mobileAccessEnabled: mobileAccessEnabled,
        permissions: permissions,
      );

  static int? _int(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
  static bool _flag(Object? v) => v == true || v == 1 || v == '1';
}

/// The company the session belongs to (`data.tenant` on login). Persisted next
/// to the token because `/auth/me` does not repeat it.
class Tenant {
  final int id;
  final String code;
  final String name;

  const Tenant({required this.id, required this.code, required this.name});

  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
        id: User._int(j['id']) ?? 0,
        code: (j['code'] ?? '') as String,
        name: (j['name'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name};
}
