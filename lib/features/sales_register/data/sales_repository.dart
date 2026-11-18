import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';

class SaleEntry {
  const SaleEntry({
    this.raw = const {},
    required this.id,
    this.buyerId,
    this.buyerName,
    this.grade,
    this.rate,
    this.pkgs,
    this.quantity,
    this.mark,
    this.invoicePrefix,
    this.invoiceNo,
    this.dealDate,
    this.cnNumber,
    this.cnDate,
    this.transport,
    this.discount,
    this.remarks,
    this.status,
    this.splitCount = 1,
    this.totalPkgs,
    this.totalQuantity,
    this.totalAmount,
  });

  /// The record as the API sent it, for fields read through [ExtraField]s.
  final Map<String, dynamic> raw;

  final int id;
  final int? buyerId;
  final String? buyerName;
  final String? grade;
  final double? rate;
  final int? pkgs;
  final double? quantity;
  final String? mark;
  final String? invoicePrefix;
  final String? invoiceNo;
  final DateTime? dealDate;
  final String? cnNumber;
  final DateTime? cnDate;
  final String? transport;
  final double? discount;
  final String? remarks;
  /// API status value; labels are in `form-options` → `sale_statuses`.
  final String? status;

  /// A sale split between buyers is stored as one record per split; the list
  /// shows it once, with the totals of all splits.
  final int splitCount;
  final int? totalPkgs;
  final double? totalQuantity;
  final double? totalAmount;

  bool get isSplit => splitCount > 1;

  double? get amount => rate == null || quantity == null ? null : rate! * quantity! - (discount ?? 0);

  /// Packages, kg and value across all splits.
  int? get allPkgs => isSplit ? totalPkgs ?? pkgs : pkgs;
  double? get allQuantity => isSplit ? totalQuantity ?? quantity : quantity;
  double? get allAmount => isSplit ? totalAmount ?? amount : amount;

  /// `GET /sales-register/{id}` has no split fields, so a refreshed detail
  /// keeps the totals from the list copy.
  SaleEntry withSplitFrom(SaleEntry? listCopy) => isSplit || listCopy == null || !listCopy.isSplit
      ? this
      : SaleEntry(
          raw: raw,
          id: id,
          buyerId: buyerId,
          buyerName: buyerName,
          grade: grade,
          rate: rate,
          pkgs: pkgs,
          quantity: quantity,
          mark: mark,
          invoicePrefix: invoicePrefix,
          invoiceNo: invoiceNo,
          dealDate: dealDate,
          cnNumber: cnNumber,
          cnDate: cnDate,
          transport: transport,
          discount: discount,
          remarks: remarks,
          status: status,
          splitCount: listCopy.splitCount,
          totalPkgs: listCopy.totalPkgs,
          totalQuantity: listCopy.totalQuantity,
          totalAmount: listCopy.totalAmount,
        );

  factory SaleEntry.fromJson(Map<String, dynamic> j) => SaleEntry(
        raw: j,
        id: J.intOr(j['id'], 0),
        buyerId: J.integer(j['buyer_id']) ?? J.integer((j['buyer'] as Map?)?['id']),
        buyerName: J.nested(j, 'buyer_name', 'buyer', 'buyer_name'),
        grade: J.str(j['tea_grade']),
        rate: J.dbl(j['rate_per_kg']),
        pkgs: J.integer(j['pkgs']),
        quantity: J.dbl(j['quantity_kg']),
        mark: J.str(j['mark']),
        invoicePrefix: J.str(j['invoice_prefix']),
        invoiceNo: J.str(j['invoice_no']),
        dealDate: J.date(j['deal_date']),
        cnNumber: J.str(j['cn_number']),
        cnDate: J.date(j['cn_date']),
        transport: J.str(j['transport']),
        discount: J.dbl(j['discount']),
        remarks: J.str(j['remarks']),
        status: J.str(j['status']),
        splitCount: J.intOr(j['split_count'], 1),
        totalPkgs: J.integer(j['aggregated_pkgs']),
        totalQuantity: J.dbl(j['aggregated_quantity_kg']),
        totalAmount: J.dbl(j['aggregated_total_amount']),
      );
}

class SalesRepository {
  const SalesRepository(this._api);
  final Api _api;

  /// What the website fills in when a garden is picked: incharge, category,
  /// location, billing company (`GET /sales-register/garden-info`).
  Future<Map<String, dynamic>?> gardenInfo(int gardenId) =>
      _api.lookup('/sales-register/garden-info', query: {'garden_id': gardenId});

  /// A lot's details from its samples and offers, by mark and invoice
  /// (`GET /sales-register/lookup-lot`).
  Future<Map<String, dynamic>?> lookupLot(String mark, String invoiceNo) =>
      _api.lookup('/sales-register/lookup-lot', query: {'mark': mark, 'invoice_no': invoiceNo});

  Future<SaleEntry> get(int id) async => SaleEntry.fromJson(await _api.one('/sales-register/$id'));

  Future<void> delete(int id) => _api.delete('/sales-register/$id');

  Future<Page<SaleEntry>> list(ListQuery q, {int page = 1}) =>
      _api.page('/sales-register', SaleEntry.fromJson, query: q.toQuery(), page: page);

  Future<void> create(Map<String, Object?> body) => _api.post('/sales-register', cleanBody(body));

  Future<void> update(int id, Map<String, Object?> body) async {
    try {
      await _api.put('/sales-register/$id', cleanBody(body));
    } on ValidationFailure catch (e) {
      // Shorten "Cannot update to 12 pkgs. Maximum allowed for this split is 10 pkgs (…)".
      final max = RegExp(r'Maximum allowed for this split is (\d+)').firstMatch(e.fieldErrors['pkgs'] ?? '')?.group(1);
      if (max == null) rethrow;
      throw ValidationFailure(e.serverMessage, {...e.fieldErrors, 'pkgs': 'At most $max packages for this sale.'});
    }
  }
}

final salesRepositoryProvider = Provider((ref) => SalesRepository(ref.watch(apiProvider)));
final salesQueryProvider = ListQueryProvider(ListQueryNotifier.new);
final salesListProvider = pagedProvider<SaleEntry>(
  salesQueryProvider,
  (ref, q, page) => ref.read(salesRepositoryProvider).list(q, page: page),
);
