import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../samples/domain/sample.dart';

/// Samples per batch when a batch doesn't say (`max_samples`), for the
/// new-batch screens before any batch exists.
const kBatchCap = 48;

class Batch {
  const Batch({required this.id, required this.name, this.date, this.status, this.notes, this.sampleCount, this.maxSamples, this.samples = const []});

  final int id;
  final String name;
  final DateTime? date;
  /// API status value; labels are in `form-options` → `batch_statuses`.
  final String? status;
  final String? notes;
  final int? sampleCount;
  final int? maxSamples;
  int get cap => maxSamples ?? kBatchCap;
  final List<Sample> samples;

  int get count => sampleCount ?? samples.length;

  factory Batch.fromJson(Map<String, dynamic> j) {
    final samples = (j['samples'] is List ? j['samples'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(Sample.fromJson)
        .toList();
    return Batch(
      id: J.intOr(j['id'], 0),
      name: J.str(j['batch_number']) ?? J.str(j['batch_name']) ?? J.str(j['name']) ?? 'Batch #${j['id']}',
      date: J.date(j['batch_date'] ?? j['date']),
      status: J.str(j['status']),
      notes: J.str(j['remarks']) ?? J.str(j['notes']),
      sampleCount: J.integer(j['samples_count'] ?? j['total_samples']),
      maxSamples: J.integer(j['max_samples']),
      samples: samples,
    );
  }
}

class BatchesRepository {
  const BatchesRepository(this._api);
  final Api _api;

  Future<Batch> get(int id) async => Batch.fromJson(await _api.one('/batches/$id'));

  Future<void> delete(int id) => _api.delete('/batches/$id');

  Future<void> update(int id, Map<String, Object?> body) => _api.put('/batches/$id', cleanBody(body));

  Future<Page<Batch>> list(ListQuery q, {int page = 1}) =>
      _api.page('/batches', Batch.fromJson, query: q.toQuery(), page: page);

  Future<void> create({String? name, required DateTime date, String? status, String? notes, required List<int> sampleIds}) =>
      _api.post('/batches', cleanBody({
        'batch_name': name,
        'batch_date': Fmt.api(date),
        'status': status,
        'remarks': notes,
        'sample_ids': sampleIds,
      }));

  /// Batches the given samples the way the website does: the server numbers
  /// them and splits them into as many batches as needed
  /// (`POST /batches/create-from-selection`).
  Future<List<Batch>> createFromSelection(List<int> sampleIds) async {
    final data = J.map(await _api.post('/batches/create-from-selection', {'sample_ids': sampleIds})) ?? const {};
    final list = data['batches'] as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map((e) => Batch.fromJson(J.map(e['batch']) ?? e)).toList();
  }

  /// Returns the batches the server created, when it reports them.
  Future<List<Batch>> createForDate(DateTime date) async {
    final data = await _api.post('/batches/create-for-date', {'date': Fmt.api(date)});
    // `{batches: [{batch: {...}}, …]}`
    final list = data is List ? data : (J.map(data)?['batches'] as List? ?? const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => Batch.fromJson(J.map(e['batch']) ?? e))
        .toList();
  }

  Future<List<Sample>> unbatched(DateTime date) async {
    final data = await _api.getData('/batches/unbatched-samples', query: {'date': Fmt.api(date)});
    final node = data is Map<String, dynamic> ? (data['samples'] ?? data['data']) : data;
    // The list ignores `date` and returns every unbatched sample, while
    // `create-for-date` batches only the samples that arrived that day.
    bool sameDay(Map<String, dynamic> s) {
      final d = J.date(s['arrival_date']);
      return d == null || (d.year == date.year && d.month == date.month && d.day == date.day);
    }

    return (node is List ? node : const []).whereType<Map<String, dynamic>>().where(sameDay).map(Sample.fromJson).toList();
  }
}

final batchesRepositoryProvider = Provider((ref) => BatchesRepository(ref.watch(apiProvider)));
final batchesQueryProvider = ListQueryProvider(ListQueryNotifier.new);
final batchesListProvider = pagedProvider<Batch>(
  batchesQueryProvider,
  (ref, q, page) => ref.read(batchesRepositoryProvider).list(q, page: page),
);

final unbatchedProvider = FutureProvider.family<List<Sample>, DateTime>(
  (ref, date) => ref.read(batchesRepositoryProvider).unbatched(date),
);
