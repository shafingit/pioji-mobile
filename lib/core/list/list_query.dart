import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Search text plus filter parameters for one list screen. Values are already
/// in the API's query format (dates as `yyyy-MM-dd`).
@immutable
class ListQuery {
  const ListQuery({this.search = '', this.params = const {}});

  final String search;
  final Map<String, String> params;

  /// Sort keys and app-only `_` keys (labels for chips) aren't filters.
  bool get hasFilters => params.keys.any((k) => !k.startsWith('_') && k != 'sort_by' && k != 'sort_dir');

  ListQuery withSearch(String value) => ListQuery(search: value, params: params);

  ListQuery withParam(String key, String? value) {
    final next = Map<String, String>.of(params);
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return ListQuery(search: search, params: next);
  }

  ListQuery cleared() => ListQuery(search: search);

  /// Keys starting with `_` are app-only (e.g. `_label.garden_id`, the name
  /// shown on a filter chip) and are never sent.
  Map<String, Object?> toQuery() => {
        'search': search,
        ...{...params}..removeWhere((k, _) => k.startsWith('_')),
      };

  /// Earliest first: `sort_dir=asc` (the API sorts since 17 Nov 2026).
  bool get oldestFirst => params['sort_dir'] == 'asc';

  /// The chip text for a picker filter's value.
  String? label(String param) => params['_label.$param'] ?? params[param];

  @override
  bool operator ==(Object other) =>
      other is ListQuery && other.search == search && mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(search, Object.hashAllUnordered(params.entries.map((e) => '${e.key}=${e.value}')));
}

class ListQueryNotifier extends Notifier<ListQuery> {
  ListQueryNotifier([this.initial = const ListQuery()]);
  final ListQuery initial;

  @override
  ListQuery build() => initial;

  void setSearch(String value) {
    if (value != state.search) state = state.withSearch(value);
  }

  void setParam(String key, String? value) => state = state.withParam(key, value);

  void replace(ListQuery query) => state = query;

  void clearFilters() => state = state.cleared();
}

typedef ListQueryProvider = NotifierProvider<ListQueryNotifier, ListQuery>;
