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

  const User({
    required this.id,
    required this.tenantId,
    required this.employeeId,
    required this.username,
    required this.email,
    required this.roleName,
    required this.mustChangePassword,
    required this.mobileAccessEnabled,
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
      );

  User copyWith({bool? mustChangePassword}) => User(
        id: id,
        tenantId: tenantId,
        employeeId: employeeId,
        username: username,
        email: email,
        roleName: roleName,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
        mobileAccessEnabled: mobileAccessEnabled,
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
