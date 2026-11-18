import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../domain/sample.dart';

class SamplesRepository {
  const SamplesRepository(this._api);
  final Api _api;

  Future<Sample> get(int id) async => Sample.fromJson(await _api.one('/samples/$id'));

  Future<Page<Sample>> list(ListQuery q, {int page = 1, int perPage = 20}) =>
      _api.page('/samples', Sample.fromJson, query: q.toQuery(), page: page, perPage: perPage);

  Future<void> update(int id, Map<String, Object?> body) => _api.put('/samples/$id', body);

  Future<void> delete(int id) => _api.delete('/samples/$id');

  /// Saves tasting scores (0–10 each) and comments; the server works out the
  /// overall score and marks the sample evaluated.
  Future<void> saveTasting(int id, Map<String, Object?> body) => _api.post('/samples/$id/tasting', cleanBody(body));

  Future<void> park(int id) => _api.post('/samples/$id/park', const <String, Object?>{});

  Future<void> unpark(int id) => _api.post('/samples/$id/unpark', const <String, Object?>{});

  /// `GET /reports/tasting`: tasted samples, filtered by `from` / `to` /
  /// `garden_id`.
  Future<List<Sample>> tastingReport(Map<String, Object?> query) async {
    final data = J.map(await _api.getData('/reports/tasting', query: cleanQuery(query)));
    final list = data?['samples'] as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Sample.fromJson).toList();
  }

  /// Earlier samples with the same garden, grade, prefix and invoice, as
  /// the website warns about (`POST /samples/check-duplicate-combination`).
  Future<List<({int id, String label})>> duplicates({required String gardenName, String? grade, String? prefix, required String invoiceNo}) async {
    try {
      final data = J.map(await _api.post('/samples/check-duplicate-combination', cleanBody({
        'garden_name': gardenName,
        'grade': grade,
        'invoice_prefix': prefix,
        'inv_no': invoiceNo,
      })));
      final list = data?['samples'] is List ? data!['samples'] as List : const [];
      return [
        for (final s in list.whereType<Map<String, dynamic>>())
          if (J.integer(s['id']) case final id?)
            (
              id: id,
              label: [J.str(s['sample_id']) ?? '#$id', if (J.date(s['arrival_date']) case final d?) Fmt.day(d), ?J.str(s['seller_name'])].join(' · '),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<Sample?> create(Map<String, Object?> body) async {
    final data = await _api.post('/samples', cleanBody(body));
    final map = J.map(data);
    return map == null ? null : Sample.fromJson(map);
  }
}

final samplesRepositoryProvider = Provider((ref) => SamplesRepository(ref.watch(apiProvider)));

final samplesQueryProvider = ListQueryProvider(ListQueryNotifier.new);

final samplesListProvider = pagedProvider<Sample>(
  samplesQueryProvider,
  (ref, q, page) => ref.read(samplesRepositoryProvider).list(q, page: page),
);
