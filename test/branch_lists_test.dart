import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tea_erp/core/list/list_query.dart';
import 'package:tea_erp/core/list/paged_notifier.dart';
import 'package:tea_erp/core/network/paginated.dart';
import 'package:tea_erp/core/storage/current_branch.dart';
import 'package:tea_erp/core/storage/prefs.dart';

void main() {
  test('a loaded list loads again when the branch changes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var fetches = 0;
    final query = ListQueryProvider(ListQueryNotifier.new);
    final list = pagedProvider<int>(query, (ref, q, page) async {
      fetches++;
      return const Page(items: [1], currentPage: 1, lastPage: 1, total: 1);
    });
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final sub = container.listen(list, (_, _) {});
    addTearDown(sub.close);

    await container.read(list.future);
    expect(fetches, 1);
    await container.read(currentBranchProvider.notifier).set(4);
    await container.read(list.future);
    expect(fetches, 2);
  });
}
