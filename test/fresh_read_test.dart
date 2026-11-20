import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/core/application/fresh_read.dart';

void main() {
  // A list that fails or comes back empty while offline, then loads.
  testWidgets('a list that failed or was empty loads again on the next open', (tester) async {
    var calls = 0;
    var online = false;
    final list = FutureProvider<List<String>>((ref) async {
      calls++;
      if (!online) throw Exception('offline');
      return ['A', 'B'];
    });
    final empty = FutureProvider<List<String>>((ref) async {
      calls++;
      return online ? ['C'] : const [];
    });

    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      child: Consumer(builder: (_, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));

    await expectLater(ref.fresh(list), throwsA(isA<Exception>()));
    expect(await ref.fresh(empty), isEmpty);

    online = true;
    expect(await ref.fresh(list), ['A', 'B']);
    expect(await ref.fresh(empty), ['C']);
    final before = calls;

    // Loaded lists are not fetched again.
    expect(await ref.fresh(list), ['A', 'B']);
    expect(await ref.fresh(empty), ['C']);
    expect(calls, before);
  });
}
