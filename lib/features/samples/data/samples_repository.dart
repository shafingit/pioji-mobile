import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/list/list_query.dart';
import '../../../core/list/paged_notifier.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_mapper.dart';
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

  /// Sends an evaluated, batched sample for retesting
  /// (`POST /samples/{id}/transfer`, reason from `sample_transfer_reasons`).
  /// The server makes a new sample from 10 g of it; returns its message.
  Future<String?> transfer(int id, String reason) async {
    final body = await _api.postBody('/samples/$id/transfer', {'transfer_reason': reason});
    return J.str(body['message']);
  }

  /// Marks samples (`POST /samples/bulk-mark`) with a mode from
  /// `form-options` → `sample_bulk_mark_modes` (for tasting, direct
  /// allocation…). Returns the server's message.
  Future<String?> bulkMark(List<int> ids, String mode) async {
    final body = await _api.postBody('/samples/bulk-mark', {'mode': mode, 'sample_ids': ids});
    return J.str(body['message']);
  }

  /// Uploads a samples sheet (`POST /samples/bulk-upload`) in one of the
  /// `form-options` → `sample_upload_formats` layouts.
  Future<({int created, int processed, List<String> errors})> bulkUpload(String path, String format) async {
    final data = J.map(await _api.post('/samples/bulk-upload', FormData.fromMap({
      'format': format,
      'file': await MultipartFile.fromFile(path, filename: path.split('/').last),
    }))) ?? const {};
    return (
      created: J.integer(data['created']) ?? 0,
      processed: J.integer(data['total_processed']) ?? 0,
      errors: [for (final e in (data['errors'] is List ? data['errors'] as List : const [])) e is Map ? (J.str(e['message']) ?? e.toString()) : e.toString()],
    );
  }

  /// Applies a marking sheet (`POST /samples/manual-marking`): marking group,
  /// mark for tasting and direct allocation per sample or offer.
  Future<String?> manualMarking(String path) async {
    final body = await _api.postBody('/samples/manual-marking', const {}, file: path);
    return J.str(body['message']);
  }

  /// Downloads a sheet template and returns its path: the bulk upload
  /// template for [format], or the manual-marking one when [format] is null.
  Future<String> template({String? format}) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${format == null ? 'manual_marking' : 'samples_$format'}_template.csv';
    try {
      await _api.dio.download(
        format == null ? '/samples/manual-marking/template' : '/samples/bulk-upload/template',
        path,
        queryParameters: {'format': ?format},
      );
    } on DioException catch (e) {
      throw mapError(e);
    }
    return path;
  }

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
