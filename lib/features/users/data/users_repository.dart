import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/application/lookup_retry.dart';
import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';
import '../../auth/domain/user.dart';

/// A role from `GET /roles`.
class Role {
  const Role({required this.slug, required this.name, this.description, this.permissionCount = 0});
  final String slug;
  final String name;
  final String? description;
  final int permissionCount;

  static Role? fromJson(Map<String, dynamic> j) {
    final slug = J.str(j['slug']);
    if (slug == null) return null;
    return Role(
      slug: slug,
      name: J.str(j['name']) ?? slug,
      description: J.str(j['description']),
      permissionCount: (j['permissions'] as List?)?.length ?? 0,
    );
  }
}

/// User management for super admins (`/users`, `/roles`).
class UsersRepository {
  const UsersRepository(this._api);
  final Api _api;

  Future<Page<User>> list(ListQuery q, {int page = 1}) => _api.page('/users', User.fromJson, query: q.toQuery(), page: page);

  Future<User> get(int id) async => User.fromJson(await _api.one('/users/$id'));

  /// Needs name, email, password and role.
  Future<void> create(Map<String, Object?> body) => _api.post('/users', cleanBody(body));

  Future<void> update(int id, Map<String, Object?> body) => _api.put('/users/$id', cleanBody(body));

  Future<void> setStatus(int id, {required bool active}) => _api.patch('/users/$id/status', {'status': active ? 'active' : 'inactive'});

  Future<void> setRole(int id, String role) => _api.put('/users/$id/role', {'role': role});

  Future<List<Role>> roles() async {
    final data = J.map(await _api.getData('/roles'));
    final list = data?['roles'] as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Role.fromJson).whereType<Role>().toList();
  }
}

final usersRepositoryProvider = Provider((ref) => UsersRepository(ref.watch(apiProvider)));
final usersQueryProvider = ListQueryProvider(ListQueryNotifier.new);
final usersListProvider = pagedProvider<User>(
  usersQueryProvider,
  (ref, q, page) => ref.read(usersRepositoryProvider).list(q, page: page),
);
final rolesProvider = FutureProvider((ref) => ref.read(usersRepositoryProvider).roles(), retry: lookupRetry);
