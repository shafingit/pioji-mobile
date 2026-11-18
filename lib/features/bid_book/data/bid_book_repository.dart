import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';

class Bid {
  const Bid({
    this.raw = const {},
    required this.id,
    required this.gardenName,
    required this.grade,
    required this.invoiceNumber,
    this.packages,
    this.netWeight,
    this.incoming,
    this.maxBid,
    this.negotiated,
    this.pencil,
    this.status,
    this.buyerId,
    this.buyerName,
    this.negotiatorId,
    this.negotiatorName,
    this.remarks,
  });

  /// The record as the API sent it, for fields read through [ExtraField]s.
  final Map<String, dynamic> raw;

  final int id;
  final String gardenName;
  final String grade;
  final String invoiceNumber;
  final int? packages;
  final double? netWeight;
  final double? incoming;
  final double? maxBid;
  final double? negotiated;
  final double? pencil;
  /// API status value; labels are in `form-options` → `bid_statuses`.
  final String? status;
  final int? buyerId;
  final String? buyerName;
  final int? negotiatorId;
  final String? negotiatorName;
  final String? remarks;

  factory Bid.fromJson(Map<String, dynamic> j) => Bid(
        raw: j,
        id: J.intOr(j['id'], 0),
        gardenName: J.nested(j, 'garden_name', 'garden', 'garden_name') ?? '–',
        grade: J.str(j['grade']) ?? '–',
        invoiceNumber: J.str(j['invoice_number']) ?? '–',
        packages: J.integer(j['packages']),
        netWeight: J.dbl(j['net_weight']),
        incoming: J.dbl(j['seller_incoming_price']),
        maxBid: J.dbl(j['max_bid']),
        negotiated: J.dbl(j['negotiated_price']),
        pencil: J.dbl(j['pencil_price']),
        status: J.str(j['status']),
        buyerId: J.integer(j['buyer_id']),
        buyerName: J.nested(j, 'buyer_name', 'buyer', 'buyer_name'),
        negotiatorId: J.integer(j['negotiator_id']),
        negotiatorName: J.nested(j, 'negotiator_name', 'negotiator'),
        remarks: J.str(j['remarks']),
      );
}

class BidBookRepository {
  const BidBookRepository(this._api);
  final Api _api;

  /// The offer-list lot for a garden and invoice: grade, packages, net
  /// weight, price (`GET /bid-book/search-offer-list`).
  Future<Map<String, dynamic>?> searchOfferList(String gardenName, String invoiceNumber) =>
      _api.lookup('/bid-book/search-offer-list', query: {'garden_name': gardenName, 'invoice_number': invoiceNumber});

  Future<Bid> get(int id) async => Bid.fromJson(await _api.one('/bid-book/$id'));

  Future<void> delete(int id) => _api.delete('/bid-book/$id');

  Future<Page<Bid>> list(ListQuery q, {int page = 1}) => _api.page('/bid-book', Bid.fromJson, query: q.toQuery(), page: page);

  /// Up to 200 lots of one tab (`open`, `parked`, …), sorted by mark then
  /// invoice, for picking several at once.
  Future<List<Bid>> listForPicking(String tab) async {
    final p = await _api.page('/bid-book', Bid.fromJson, query: {'tab': tab, 'sort_by': 'garden_name', 'sort_dir': 'asc'}, perPage: 200);
    return p.items;
  }

  Future<void> create(Map<String, Object?> body) => _api.post('/bid-book', cleanBody(body));

  Future<void> update(int id, Map<String, Object?> body) => _api.put('/bid-book/$id', body);

  /// `POST /bid-book/bulk`: creates several lots. Returns the new ids and,
  /// per row index, the server's first error for rows that failed.
  Future<({List<int> created, Map<int, String> errors})> bulkCreate(List<Map<String, Object?>> items) async {
    final data = J.map(await _api.post('/bid-book/bulk', {'items': [for (final i in items) cleanBody(i)]})) ?? const {};
    final errors = <int, String>{};
    for (final e in (data['errors'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      final index = J.integer(e['index']);
      final fields = J.map(e['errors']) ?? const {};
      if (index == null) continue;
      // A raw database error isn't shown as is; field errors are.
      final first = fields.entries.where((f) => f.key != 'exception').map((f) => f.value is List ? (f.value as List).first.toString() : f.value.toString()).firstOrNull;
      errors[index] = first ?? "The server couldn't save this lot.";
    }
    return (created: J.ints(data['created_ids']), errors: errors);
  }

  /// `PATCH /bid-book/bulk`: sets the asking price and/or max bid on several lots.
  Future<void> bulkUpdate(List<int> ids, {double? incoming, double? maxBid}) => _api.patch('/bid-book/bulk', {
        'ids': ids,
        'seller_incoming_price': ?incoming,
        'max_bid': ?maxBid,
      });
}

final bidBookRepositoryProvider = Provider((ref) => BidBookRepository(ref.watch(apiProvider)));
final bidBookQueryProvider = ListQueryProvider(() => ListQueryNotifier(const ListQuery(params: {'tab': 'open'})));
final bidBookListProvider = pagedProvider<Bid>(
  bidBookQueryProvider,
  (ref, q, page) => ref.read(bidBookRepositoryProvider).list(q, page: page),
);
