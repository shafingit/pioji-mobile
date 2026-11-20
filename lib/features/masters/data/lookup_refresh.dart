import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/application/fresh_read.dart';
import '../../users/data/users_repository.dart';
import 'form_options.dart';
import 'masters_repository.dart';

/// Called when the phone comes back online: dropdown lists that failed or
/// loaded empty while offline are fetched again. Lists that loaded fine are
/// left alone.
void refreshFailedLookups(WidgetRef ref) {
  if (ref.isStale(formOptionsProvider, isEmpty: (o) => o.isEmpty)) ref.invalidate(formOptionsProvider);
  for (final p in <FutureProvider<Object?>>[
    gardensProvider,
    buyersProvider,
    sellersProvider,
    negotiatorsProvider,
    postingListsProvider,
    invoiceTypesProvider,
    billingCompaniesProvider,
    gradesProvider,
    rolesProvider,
  ]) {
    if (ref.isStale(p)) ref.invalidate(p);
  }
  if (ref.isStale(courierOptionsProvider, isEmpty: (o) => o.services.isEmpty && o.addresses.isEmpty)) {
    ref.invalidate(courierOptionsProvider);
  }
  if (ref.isStale(typeLinksProvider, isEmpty: (l) => l.isEmpty)) ref.invalidate(typeLinksProvider);
  // Per-garden and per-buyer lists are small; load them again on next use.
  ref.invalidate(gardenHistoryProvider);
  ref.invalidate(gardenOptionsProvider);
  ref.invalidate(buyerPostingListsProvider);
}
