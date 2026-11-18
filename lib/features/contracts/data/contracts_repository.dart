import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';
import '../../masters/data/masters_repository.dart';

class ContractItem {
  const ContractItem({this.grade, this.pricePerKg, this.quantity, this.currency});
  final String? grade;
  final double? pricePerKg;
  final double? quantity;
  /// From `form-options` → `currencies`.
  final String? currency;

  double get value => (pricePerKg ?? 0) * (quantity ?? 0);

  factory ContractItem.fromJson(Map<String, dynamic> j) => ContractItem(
        grade: J.str(j['tea_grade']) ?? J.str(j['tea_grade_description']),
        pricePerKg: J.dbl(j['price_per_kg']),
        quantity: J.dbl(j['quantity']),
        currency: J.str(j['currency']),
      );

  Map<String, Object?> toJson() => {'tea_grade': grade, 'price_per_kg': pricePerKg, 'quantity': quantity, 'currency': currency};
}

class Contract {
  const Contract({
    required this.id,
    required this.title,
    this.number,
    this.sellerId,
    this.buyerId,
    this.gardenId,
    this.gardenName,
    this.sellerName,
    this.buyerName,
    this.effective,
    this.expiry,
    this.promptDays,
    this.discount,
    this.status,
    this.terms,
    this.items = const [],
  });

  final int id;
  final String title;
  final String? number;
  final int? sellerId;
  final int? buyerId;
  final int? gardenId;
  final String? gardenName;
  final String? sellerName;
  final String? buyerName;
  final DateTime? effective;
  final DateTime? expiry;
  final int? promptDays;
  final double? discount;
  /// API status value; labels are in `form-options` → `contract_statuses`.
  final String? status;
  final String? terms;
  final List<ContractItem> items;

  bool get expiringSoon =>
      status == 'active' && expiry != null && expiry!.difference(DateTime.now()).inDays <= 7 && expiry!.isAfter(DateTime.now());

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: J.intOr(j['id'], 0),
        title: (J.str(j['contract_title']) ?? 'Contract #${j['id']}').replaceAll(RegExp(r'\s+'), ' '),
        number: J.str(j['contract_number']),
        sellerId: J.integer(j['seller_id']),
        buyerId: J.integer(j['buyer_id']),
        gardenId: J.integer(j['garden_id']),
        gardenName: J.nested(j, 'garden_name', 'garden', 'garden_name'),
        sellerName: J.nested(j, 'seller_name', 'seller', 'seller_name'),
        buyerName: J.nested(j, 'buyer_name', 'buyer', 'buyer_name'),
        effective: J.date(j['effective_date']),
        expiry: J.date(j['expiry_date']),
        promptDays: J.integer(j['prompt_days']),
        discount: J.dbl(j['discount']),
        status: J.str(j['status']),
        terms: J.str(j['terms_and_conditions']),
        items: ((j['contract_items'] ?? j['items']) is List ? (j['contract_items'] ?? j['items']) as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(ContractItem.fromJson)
            .toList(),
      );
}

class ContractsRepository {
  const ContractsRepository(this._api);
  final Api _api;

  /// The seller's gardens with their grades (`GET /contracts/gardens-by-seller`).
  Future<List<({MasterItem garden, List<GardenGrade> grades})>> gardensBySeller(int sellerId) async {
    final data = await _api.lookup('/contracts/gardens-by-seller', query: {'seller_id': sellerId});
    final list = data?['gardens'] is List ? data!['gardens'] as List : const [];
    return [
      for (final g in list.whereType<Map<String, dynamic>>())
        if (MasterItem.fromJson(g) case final garden?)
          (
            garden: garden,
            grades: [
              for (final x in (g['grades'] is List ? g['grades'] as List : const []).whereType<Map<String, dynamic>>())
                if (J.str(x['grade_code']) case final code?) GardenGrade(id: J.integer(x['id']), code: code, name: J.str(x['grade_name']) ?? code),
            ],
          ),
    ];
  }

  Future<Contract> get(int id) async => Contract.fromJson(await _api.one('/contracts/$id'));

  Future<void> delete(int id) => _api.delete('/contracts/$id');

  Future<void> update(int id, Map<String, Object?> body) => _api.put('/contracts/$id', cleanBody(body));

  Future<Page<Contract>> list(ListQuery q, {int page = 1}) =>
      _api.page('/contracts', Contract.fromJson, query: q.toQuery(), page: page);

  Future<void> create(Map<String, Object?> body) => _api.post('/contracts', cleanBody(body));
}

final contractsRepositoryProvider = Provider((ref) => ContractsRepository(ref.watch(apiProvider)));
final contractsQueryProvider = ListQueryProvider(ListQueryNotifier.new);
final contractsListProvider = pagedProvider<Contract>(
  contractsQueryProvider,
  (ref, q, page) => ref.read(contractsRepositoryProvider).list(q, page: page),
);
