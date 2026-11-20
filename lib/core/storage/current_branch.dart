import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// The branch (office) this phone works from, like the website's Switch
/// Branch: its id from `GET /form-options` → `offices`, or null for none.
/// Every new record and list request carries it (see the API interceptor).
class CurrentBranch extends Notifier<int?> {
  static const _key = 'branch_id';

  @override
  int? build() => ref.read(sharedPrefsProvider).getInt(_key);

  Future<void> set(int? id) async {
    state = id;
    final prefs = ref.read(sharedPrefsProvider);
    if (id == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, id);
    }
  }
}

final currentBranchProvider = NotifierProvider<CurrentBranch, int?>(CurrentBranch.new);

/// Records shared by the whole company, not kept per branch: creating one
/// must not tie it to the branch this phone is on.
const _companyWide = ['/users', '/buyers', '/sellers'];

/// Adds [branchId] to a request the way the website's branch scoping
/// needs it: `branch_id` on list reads and on new records (JSON or a form
/// with a file), never on edits (an edited record keeps its own branch),
/// company-wide records or sign-in calls.
void applyBranch({
  required String method,
  required String path,
  required Map<String, dynamic> query,
  required Map<String, dynamic> headers,
  required Object? body,
  required int branchId,
  required void Function(Map<String, dynamic> query) setQuery,
  required void Function(Object? body) setBody,
}) {
  if (path.contains('/auth/')) return;
  headers['X-Branch-Id'] = '$branchId';
  switch (method.toUpperCase()) {
    case 'GET':
      if (!query.containsKey('branch_id')) setQuery({...query, 'branch_id': branchId});
    case 'POST':
      if (_companyWide.any((p) => path == p || path.startsWith('$p/'))) return;
      // A POST that stands in for PUT/PATCH (`_method`) is an edit.
      if (body is Map<String, dynamic> && !body.containsKey('_method')) {
        setBody({'branch_id': branchId, ...body});
      } else if (body is FormData) {
        final keys = body.fields.map((f) => f.key);
        if (!keys.contains('branch_id') && !keys.contains('_method')) body.fields.add(MapEntry('branch_id', '$branchId'));
      } else if (body == null) {
        setBody({'branch_id': branchId});
      }
  }
}
