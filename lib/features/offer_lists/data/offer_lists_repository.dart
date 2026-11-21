import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';

class OfferList {
  const OfferList({
    this.raw = const {},
    required this.id,
    this.date,
    this.gardenId,
    this.gardenName,
    this.grade,
    this.invPrefix,
    this.invNo,
    this.pkgs,
    this.nett,
    this.totalKgs,
    this.grossWeight,
    this.packingDate,
    this.type,
    this.price,
    this.currency,
    this.promptDays,
    this.parties = const [],
    this.buyers = const [],
  });

  /// The record as the API sent it, for fields read through [ExtraField]s.
  final Map<String, dynamic> raw;

  final int id;
  final DateTime? date;
  final int? gardenId;
  final String? gardenName;
  final String? grade;
  final String? invPrefix;
  final String? invNo;
  final double? pkgs;
  final double? nett;
  final double? totalKgs;
  final double? grossWeight;
  final DateTime? packingDate;
  final String? type;
  final double? price;
  final String? currency;
  final int? promptDays;
  /// party_1 … party_10, filled ones only, in order.
  final List<String> parties;
  final List<String> buyers;

  String get title => [gardenName ?? 'Garden #${gardenId ?? '–'}', ?grade].join(' · ');

  /// Marked for tasting (`tasting_mark`).
  bool get tastingMark => J.boolOr(raw['tasting_mark'], false);

  factory OfferList.fromJson(Map<String, dynamic> j) => OfferList(
        raw: j,
        id: J.intOr(j['id'], 0),
        date: J.date(j['date']),
        gardenId: J.integer(j['garden_id']),
        gardenName: J.nested(j, 'garden_name', 'garden', 'garden_name'),
        grade: J.code(j['grade']),
        invPrefix: J.str(j['inv_prefix']) ?? J.str(j['inv_pretx']),
        invNo: J.str(j['inv_no']),
        pkgs: J.dbl(j['pkgs']),
        nett: J.dbl(j['nett']),
        totalKgs: J.dbl(j['ttl_kgs']),
        grossWeight: J.dbl(j['gross_weight']),
        packingDate: J.date(j['d_o_packing']),
        type: J.str(j['type']),
        price: J.dbl(j['price']),
        currency: J.str(j['currency']),
        promptDays: J.integer(j['prompt_days']),
        parties: [
          for (var i = 1; i <= 10; i++)
            if ((J.str(j['party_$i']) ?? '').trim().isNotEmpty) J.str(j['party_$i'])!.trim(),
        ],
        buyers: (j['buyers'] is List ? j['buyers'] as List : const [])
            .map((b) => b is Map ? J.str(b['name']) : J.str(b))
            .whereType<String>()
            .toList(),
      );
}

class OfferListsRepository {
  const OfferListsRepository(this._api);
  final Api _api;

  Future<OfferList> get(int id) async => OfferList.fromJson(await _api.one('/offer-lists/$id'));

  Future<void> delete(int id) => _api.delete('/offer-lists/$id');

  Future<Page<OfferList>> list(ListQuery q, {int page = 1}) =>
      _api.page('/offer-lists', OfferList.fromJson, query: q.toQuery(), page: page);

  Future<void> create(Map<String, Object?> body) => _api.post('/offer-lists', cleanBody(body));

  /// Marks [offers] for tasting. The API has no offer route for this, so
  /// it sends the website's marking sheet
  /// (`POST /samples/manual-marking`) with only the tasting column, which
  /// leaves marking groups and direct allocation alone. The server looks
  /// the offers up within the sheet's `branch_id`, so each branch's offers
  /// go in their own sheet with that branch (empty for none).
  Future<void> markForTasting(List<OfferList> offers) async {
    final byBranch = <String, List<int>>{};
    for (final o in offers) {
      (byBranch[J.str(o.raw['branch_id']) ?? ''] ??= []).add(o.id);
    }
    for (final e in byBranch.entries) {
      await _api.post('/samples/manual-marking', FormData.fromMap({
        'branch_id': e.key,
        'file': MultipartFile.fromString(
          tastingSheet(e.value),
          filename: 'tasting.csv',
          contentType: DioMediaType('text', 'csv'),
        ),
      }));
    }
  }

  /// Parties left out of [body] are sent as null: the server clears a party
  /// only when it gets null, and keeps it when the key is missing.
  Future<void> update(int id, Map<String, Object?> body) => _api.put('/offer-lists/$id', {
        ...cleanBody(body),
        for (var i = 1; i <= 10; i++)
          if (!body.containsKey('party_$i')) 'party_$i': null,
      });
}

final offerListsRepositoryProvider = Provider((ref) => OfferListsRepository(ref.watch(apiProvider)));
final offerListsQueryProvider = ListQueryProvider(ListQueryNotifier.new);
final offerListsListProvider = pagedProvider<OfferList>(
  offerListsQueryProvider,
  (ref, q, page) => ref.read(offerListsRepositoryProvider).list(q, page: page),
);

/// The marking sheet that marks offers [ids] for tasting.
String tastingSheet(List<int> ids) => [
      'item_type,item_ref,mark_for_tasting',
      for (final id in ids) 'offer_list,$id,1',
    ].join('\n');
