import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';

/// A pickable record: garden, buyer, seller, courier service, address, user,
/// posting list.
class MasterItem {
  const MasterItem(this.id, this.name, {this.subtitle});
  final int id;
  final String name;
  final String? subtitle;

  static MasterItem? fromJson(Map<String, dynamic> j) {
    final id = J.integer(j['id']);
    if (id == null) return null;
    final name = J.str(j['garden_name']) ??
        J.str(j['buyer_name']) ??
        J.str(j['seller_name']) ??
        J.str(j['company_name']) ??
        J.str(j['address_title']) ??
        J.str(j['name']) ??
        J.str(j['title']) ??
        '#$id';
    final subtitle = J.str(j['city']) ??
        J.str(j['tea_estate_name']) ??
        J.str(j['contact_person']) ??
        J.str(j['email']);
    return MasterItem(id, name, subtitle: subtitle == name ? null : subtitle);
  }

  static List<MasterItem> listFrom(Object? node) {
    if (node is Map<String, dynamic>) {
      return Page.parse<MasterItem?>(node, MasterItem.fromJson).items.whereType<MasterItem>().toList();
    }
    if (node is! List) return const [];
    return node.whereType<Map<String, dynamic>>().map(MasterItem.fromJson).whereType<MasterItem>().toList();
  }
}

/// A grade set up for a garden.
class GardenGrade {
  const GardenGrade({this.id, required this.code, required this.name, this.invoiceType});
  final int? id;
  final String code;
  final String name;
  final String? invoiceType;
}

/// A garden's grades, invoice types and invoice prefixes per type.
class GardenOptions {
  const GardenOptions({this.grades = const [], this.invoiceTypes = const [], this.prefixes = const {}});
  static const empty = GardenOptions();

  final List<GardenGrade> grades;
  final List<String> invoiceTypes;
  final Map<String, List<String>> prefixes;

  GardenGrade? grade(String? code) => grades.where((g) => g.code == code).firstOrNull;

  /// Prefixes for an invoice type, or every prefix when the type is unknown.
  List<String> prefixesFor(String? invoiceType) =>
      prefixes[invoiceType] ?? {for (final l in prefixes.values) ...l}.toList();
}

/// Which invoice types each grade and each prefix belong to, from
/// `GET /grades` and `GET /invoice-prefixes` (keys upper-case).
class TypeLinks {
  const TypeLinks({this.grades = const {}, this.prefixes = const {}, this.standard = const {}, this.labels = const {}});
  static const empty = TypeLinks();

  final Map<String, Set<String>> grades;
  final Map<String, Set<String>> prefixes;

  /// Invoice types `GET /invoice-types` marks `is_standard` (brokens,
  /// fannings, dust, whole leaf), and every type's label.
  final Set<String> standard;
  final Map<String, String> labels;

  String label(String type) => labels[type] ?? type;

  /// The garden's prefixes, each with the invoice type it stands for. A
  /// prefix the garden lists under a non-standard type (the default "ctc"
  /// set-up) is split into the standard types the master list gives it, so
  /// "C" becomes "C · Brokens" and "C · Fannings".
  List<({String prefix, String type})> pairs(Map<String, List<String>> garden) {
    final out = <({String prefix, String type})>[];
    void add(String p, String t) {
      if (!out.any((x) => x.prefix == p && x.type == t)) out.add((prefix: p, type: t));
    }
    for (final e in garden.entries) {
      for (final p in e.value) {
        final global = prefixTypes(p).where(standard.contains).toList();
        if (standard.contains(e.key) || global.isEmpty) {
          add(p, e.key);
        } else {
          for (final t in global) {
            add(p, t);
          }
        }
      }
    }
    return out;
  }

  /// The invoice types [grade] really is: its standard types from the grade
  /// master, else the type the garden set-up gives it ([gardenType]).
  Set<String> effectiveTypes(String grade, [String? gardenType]) {
    final t = gradeTypes(grade).where(standard.contains).toSet();
    if (t.isNotEmpty) return t;
    return gardenType == null ? const {} : {gardenType};
  }

  /// The one standard type [grade] belongs to, if it has exactly one.
  String? gradeType(String? grade) {
    final t = gradeTypes(grade).where(standard.contains).toList();
    return t.length == 1 ? t.single : null;
  }

  bool get isEmpty => grades.isEmpty && prefixes.isEmpty;

  Set<String> gradeTypes(String? grade) => grade == null ? const {} : grades[grade.toUpperCase()] ?? const {};
  Set<String> prefixTypes(String? prefix) => prefix == null ? const {} : prefixes[prefix.toUpperCase()] ?? const {};

  /// Whether [prefix] is used for [grade]'s invoice type.
  bool fits(String prefix, String? grade) => prefixTypes(prefix).intersection(gradeTypes(grade)).isNotEmpty;

  /// Whether [grade] can carry [prefix]; unknown either way counts as yes.
  bool gradeFitsPrefix(String grade, String prefix) {
    final g = gradeTypes(grade);
    final p = prefixTypes(prefix);
    return g.isEmpty || p.isEmpty || g.intersection(p).isNotEmpty;
  }
}

/// The prefix to preselect for [grade]: of the garden's [prefixes], the
/// ones used for the grade's invoice type; if one is left that's it,
/// otherwise the one this garden last used with the grade ([recent]).
String? suggestPrefix({required List<String> prefixes, required String? grade, required TypeLinks links, required Map<String, String> recent}) {
  if (prefixes.isEmpty) return null;
  if (prefixes.length == 1) return prefixes.single;
  if (grade == null || grade.isEmpty) return null;
  final fitting = prefixes.where((p) => links.fits(p, grade)).toList();
  final pool = fitting.isEmpty ? prefixes : fitting;
  if (pool.length == 1) return pool.single;
  final last = recent[grade.toUpperCase()];
  return last != null && pool.contains(last) ? last : null;
}

/// What a garden's latest samples used (keys upper-case).
class GardenHistory {
  const GardenHistory({this.prefixByGrade = const {}, this.gradesByPrefix = const {}});
  static const empty = GardenHistory();

  final Map<String, String> prefixByGrade;
  final Map<String, List<String>> gradesByPrefix;

  List<String> gradesFor(String? prefix) => prefix == null ? const [] : gradesByPrefix[prefix.toUpperCase()] ?? const [];
}

/// Lookup lists for pickers. A failure returns an empty list, which makes the
/// picker fall back to typing an ID.
class MastersRepository {
  const MastersRepository(this._api);
  final Api _api;

  /// Every page of a small list (buyers, sellers, negotiators, posting lists).
  Future<List<MasterItem>> list(String path, {Map<String, Object?> query = const {}}) async {
    try {
      final out = <MasterItem>[];
      var page = 1;
      while (page <= 10) {
        final p = await _api.page<MasterItem?>(path, MasterItem.fromJson, query: query, page: page, perPage: 100);
        out.addAll(p.items.whereType<MasterItem>());
        if (!p.hasMore) break;
        page++;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// A large list in one call (gardens: about 2,200 records), sorted by name.
  /// The picker searches it on the phone.
  Future<List<MasterItem>> all(String path) async {
    try {
      final p = await _api.page<MasterItem?>(path, MasterItem.fromJson, perPage: 5000);
      return p.items.whereType<MasterItem>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  /// Server-side search, used when the full list couldn't load.
  Future<List<MasterItem>> search(String path, String query) async {
    try {
      final p = await _api.page<MasterItem?>(path, MasterItem.fromJson, query: {'search': query}, perPage: 30);
      return p.items.whereType<MasterItem>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Grade codes from `GET /grades` (`grade_name`/`grade_code`), every page.
  Future<List<String>> grades() async {
    try {
      final names = <String>{};
      var page = 1;
      while (page <= 10) {
        final p = await _api.page<String?>(
          '/grades',
          (g) => J.str(g['grade_name']) ?? J.str(g['grade_code']) ?? J.str(g['name']),
          page: page,
          perPage: 100,
        );
        names.addAll(p.items.whereType<String>());
        if (!p.hasMore) break;
        page++;
      }
      return names.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// What each grade and prefix is used for, from the master lists. A page
  /// that fails is skipped, so one bad record doesn't lose the rest.
  Future<TypeLinks> typeLinks() async {
    final grades = <String, Set<String>>{};
    final prefixes = <String, Set<String>>{};
    Future<void> each(String path, int perPage, void Function(Map<String, dynamic>) add) async {
      var last = 1;
      for (var page = 1; page <= last && page <= 40; page++) {
        // Staging sometimes answers a page with a 500 "database error";
        // one retry usually gets it.
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            final p = await _api.page<Map<String, dynamic>>(path, (x) => x, page: page, perPage: perPage);
            p.items.forEach(add);
            last = p.lastPage;
            break;
          } catch (_) {
            if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
      }
    }

    await each('/grades', 100, (g) {
      final type = J.str(g['invoice_type']);
      if (type == null) return;
      for (final key in {J.str(g['grade_code']), J.str(g['grade_name'])}.whereType<String>()) {
        (grades[key.toUpperCase()] ??= {}).add(type);
      }
    });
    await each('/invoice-prefixes', 100, (x) {
      final prefix = J.str(x['prefix']);
      final type = J.str(x['invoice_type']);
      if (prefix != null && type != null) (prefixes[prefix.toUpperCase()] ??= {}).add(type);
    });
    final standard = <String>{};
    final labels = <String, String>{};
    try {
      final data = await _api.getData('/invoice-types');
      for (final t in (data is List ? data : const []).whereType<Map<String, dynamic>>()) {
        final type = J.str(t['type']);
        if (type == null) continue;
        labels[type] = J.str(t['label']) ?? type;
        if (J.boolOr(t['is_standard'], false)) standard.add(type);
      }
    } catch (_) {}
    return TypeLinks(grades: grades, prefixes: prefixes, standard: standard, labels: labels);
  }

  /// What this garden's latest samples used: the last prefix per grade and
  /// the grades per prefix, most recent first.
  Future<GardenHistory> gardenHistory(int gardenId) async {
    String? code(Object? v) => v is Map ? J.str(v['code']) : J.str(v);
    try {
      final p = await _api.page<Map<String, dynamic>>('/samples', (s) => s, query: {'garden_id': gardenId, 'sort_by': 'created_at', 'sort_dir': 'desc'}, perPage: 100);
      final byGrade = <String, String>{};
      final byPrefix = <String, List<String>>{};
      for (final s in p.items) {
        final grade = code(s['grade'])?.toUpperCase();
        final prefix = (code(s['invoice_prefix']) ?? J.str(s['inv_pretx']))?.toUpperCase();
        if (grade == null || prefix == null || prefix.isEmpty) continue;
        byGrade.putIfAbsent(grade, () => prefix);
        final list = byPrefix[prefix] ??= [];
        if (!list.contains(grade)) list.add(grade);
      }
      return GardenHistory(prefixByGrade: byGrade, gradesByPrefix: byPrefix);
    } catch (_) {
      return GardenHistory.empty;
    }
  }

  /// Invoice types from `GET /invoice-types`: the stored value and its label.
  Future<List<({String value, String label})>> invoiceTypes() async {
    try {
      final data = await _api.getData('/invoice-types');
      final list = data is List ? data : (J.map(data)?['types'] as List? ?? const []);
      return [
        for (final t in list.whereType<Map<String, dynamic>>())
          if (J.str(t['type']) != null) (value: J.str(t['type'])!, label: J.str(t['label']) ?? J.str(t['type'])!),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Companies a sample can be for (`GET /billing-companies`): the code is
  /// what samples store in `for_company`.
  Future<List<({String code, String name})>> billingCompanies() async {
    try {
      final p = await _api.page<({String code, String name})?>(
        '/billing-companies',
        (j) {
          final code = J.str(j['code']);
          return code == null ? null : (code: code, name: J.str(j['company_name']) ?? code);
        },
        perPage: 200,
      );
      return p.items.whereType<({String code, String name})>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// What one garden offers (`GET /gardens/{id}/options`): its grades with
  /// their invoice type, its invoice types and the prefixes for each.
  Future<GardenOptions> gardenOptions(int gardenId) async {
    try {
      final data = J.map(await _api.getData('/gardens/$gardenId/options')) ?? const {};
      final prefixes = J.map(data['invoice_prefixes']) ?? const {};
      return GardenOptions(
        grades: [
          for (final g in (data['grades'] is List ? data['grades'] as List : const []).whereType<Map<String, dynamic>>())
            if (J.str(g['grade_code']) case final code?)
              GardenGrade(id: J.integer(g['id']), code: code, name: J.str(g['grade_name']) ?? code, invoiceType: J.str(g['invoice_type'])),
        ],
        invoiceTypes: [for (final t in (data['invoice_types'] is List ? data['invoice_types'] as List : const [])) t.toString()],
        prefixes: {
          for (final e in prefixes.entries)
            if (e.value is List) e.key: [for (final p in e.value as List) p.toString()],
        },
      );
    } catch (_) {
      return GardenOptions.empty;
    }
  }

  /// Quick-register a buyer or seller by name (`POST /buyers`, `POST /sellers`).
  /// The server fills the rest (code, type, placeholder email).
  Future<MasterItem> create(String path, String nameKey, String name) async {
    final data = J.map(await _api.post(path, {nameKey: name})) ?? const {};
    final record = data.containsKey('id') ? data : data.values.whereType<Map<String, dynamic>>().firstWhere((v) => v.containsKey('id'), orElse: () => const {});
    return MasterItem.fromJson(record) ?? (throw StateError('The server did not return the new record.'));
  }

  /// Posting lists with items still to send to a buyer
  /// (`GET /courier-entries/pending-posting-lists/{buyer}`).
  Future<List<MasterItem>> pendingPostingLists(int buyerId) async {
    final data = await _api.lookup('/courier-entries/pending-posting-lists/$buyerId');
    final lists = data?['lists'] is List ? data!['lists'] as List : const [];
    return [
      for (final l in lists.whereType<Map<String, dynamic>>())
        if (J.integer(l['id']) case final id?)
          MasterItem(id, J.str(l['name']) ?? '#$id', subtitle: '${(l['items'] as List?)?.length ?? 0} items'),
    ];
  }

  Future<List<MasterItem>> buyers() async {
    final direct = await list('/buyers');
    if (direct.isNotEmpty) return direct;
    // Fallback: today's allocation grid includes the buyer list.
    try {
      final data = J.map(await _api.getData('/samples-offered-today')) ?? const {};
      return MasterItem.listFrom(data['available_buyers']);
    } catch (_) {
      return const [];
    }
  }

  Future<({List<MasterItem> services, List<MasterItem> addresses})> courierOptions() async {
    try {
      final data = J.map(await _api.getData('/courier-entries/services')) ?? const {};
      return (
        services: MasterItem.listFrom(data['courier_services']),
        addresses: MasterItem.listFrom(data['courier_addresses']),
      );
    } catch (_) {
      return (services: const <MasterItem>[], addresses: const <MasterItem>[]);
    }
  }
}

final mastersRepositoryProvider = Provider((ref) => MastersRepository(ref.watch(apiProvider)));

/// Every garden, loaded once; the picker filters it as you type.
final gardensProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).all('/gardens'));
final buyersProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).buyers());
final sellersProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).list('/sellers'));
final negotiatorsProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).list('/negotiators'));
final postingListsProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).list('/posting-lists'));

/// Posting lists with items still to send to one buyer.
final buyerPostingListsProvider = FutureProvider.family<List<MasterItem>, int>(
  (ref, buyerId) => ref.read(mastersRepositoryProvider).pendingPostingLists(buyerId),
);

final invoiceTypesProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).invoiceTypes());
final billingCompaniesProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).billingCompanies());

/// Grades, invoice types and prefixes for one garden.
final gardenOptionsProvider = FutureProvider.family<GardenOptions, int>(
  (ref, gardenId) => ref.read(mastersRepositoryProvider).gardenOptions(gardenId),
);
final courierOptionsProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).courierOptions());
final gradesProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).grades());
final typeLinksProvider = FutureProvider((ref) => ref.read(mastersRepositoryProvider).typeLinks());

/// What one garden's latest samples used.
final gardenHistoryProvider = FutureProvider.family<GardenHistory, int>(
  (ref, gardenId) => ref.read(mastersRepositoryProvider).gardenHistory(gardenId),
);

