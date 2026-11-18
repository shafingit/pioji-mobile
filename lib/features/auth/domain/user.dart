import '../../../core/utils/json.dart';

/// The signed-in user from `GET /auth/me`.
class User {
  const User({
    this.id,
    required this.name,
    required this.email,
    this.phone,
    this.role,
    this.roleText,
    this.department,
    this.status,
    this.buyerIds = const [],
    this.officeIds = const [],
    this.permissions,
  });

  final int? id;
  final String name;
  final String email;
  final String? phone;

  /// Slug, e.g. `super_admin`; [roleText] is the label ("Super Admin").
  final String? role;
  final String? roleText;
  final String? department;
  final String? status;
  final List<int> buyerIds;
  final List<int> officeIds;

  /// Null when unknown (e.g. offline with a cached user): then [can] allows
  /// everything and the server decides.
  final Set<String>? permissions;

  bool can(String permission) => permissions == null || permissions!.contains(permission);

  bool get isSuperAdmin => role == 'super_admin';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: J.integer(j['id']),
        name: J.str(j['name']) ?? 'Admin',
        email: J.str(j['email']) ?? '',
        phone: J.str(j['phone']),
        role: J.str(j['role']),
        roleText: J.str(j['role_text']),
        department: J.str(j['department']),
        status: J.str(j['status']),
        buyerIds: J.ints(j['buyer_ids']),
        officeIds: J.ints(j['office_ids']),
        permissions: j['permissions'] is List ? {for (final p in j['permissions'] as List) p.toString()} : null,
      );

  String get initial => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

sealed class AuthState {
  const AuthState();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);
  final User user;
}

class SignedOut extends AuthState {
  const SignedOut({this.sessionExpired = false});
  final bool sessionExpired;
}
