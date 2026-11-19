import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/network/api.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_mapper.dart';
import '../../../core/utils/json.dart';

/// One tester's C/T/S/B scores (0–100) for a sample.
class TesterScore {
  const TesterScore({required this.testerId, required this.c, required this.t, required this.s, required this.b, this.extras = const {}, this.remarks});
  final int testerId;
  final double c, t, s, b;

  /// Values from `form-options` lists, by API key (see [extraFields]).
  final Map<String, String> extras;
  final String? remarks;

  /// Per-tester choices the website records, with their `form-options` list.
  static const extraFields = {
    'color_shade': (label: 'Colour', list: 'testing_color_shades'),
    'leaf_grade': (label: 'Leaf', list: 'testing_leaf_grades'),
    'report': (label: 'Report', list: 'testing_reports'),
    'ch_defect': (label: 'CH', list: 'testing_ch_defects'),
  };

  static TesterScore? fromJson(Map<String, dynamic> j) {
    final id = J.integer(j['tester_id']);
    if (id == null) return null;
    return TesterScore(
      testerId: id,
      c: J.dbl(j['c_score']) ?? 0,
      t: J.dbl(j['t_score']) ?? 0,
      s: J.dbl(j['s_score']) ?? 0,
      b: J.dbl(j['b_score']) ?? 0,
      extras: {
        for (final k in extraFields.keys)
          if (J.str(j[k]) case final v?) k: v,
      },
      remarks: J.str(j['remarks']),
    );
  }

  Map<String, Object?> toJson() => {
        'tester_id': testerId,
        'c_score': c,
        't_score': t,
        's_score': s,
        'b_score': b,
        ...extras,
        if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
      };
}

/// A sample's result in a batch testing session.
class SampleResult {
  const SampleResult({
    required this.id,
    this.sequence,
    this.status,
    this.statusLabel,
    this.scores = const [],
    this.average,
    this.overall,
    this.remarks,
    this.sampleId,
    this.sampleCode,
    this.title,
    this.invoice,
  });

  final int id;
  final int? sequence;
  final String? status;
  final String? statusLabel;
  final List<TesterScore> scores;

  /// "65-60-55-50": average C-T-S-B.
  final String? average;
  final double? overall;
  final String? remarks;
  final int? sampleId;
  final String? sampleCode;

  /// Garden and grade, e.g. "SANSAAR · BOP".
  final String? title;
  final String? invoice;

  bool get done => status == 'completed';

  static SampleResult? fromJson(Map<String, dynamic> j) {
    final id = J.integer(j['sample_result_id']);
    if (id == null) return null;
    final s = J.map(j['sample']) ?? const {};
    return SampleResult(
      id: id,
      sequence: J.integer(j['sample_sequence']),
      status: J.str(j['status']),
      statusLabel: J.str(j['status_label']),
      scores: [
        for (final t in (j['tester_results'] is List ? j['tester_results'] as List : const []).whereType<Map<String, dynamic>>())
          if (TesterScore.fromJson(t) case final score?) score,
      ],
      average: J.str(j['average_score_result']),
      overall: J.dbl(j['overall_average']),
      remarks: J.str(j['sample_remarks']),
      sampleId: J.integer(s['id']) ?? J.integer(j['sample_id']),
      sampleCode: J.str(s['sample_id']) ?? J.str(j['sample_code']),
      title: _joinOrNull([J.str(s['garden_name']), J.code(s['grade'])], ' · '),
      invoice: _joinOrNull([J.code(s['invoice_prefix']), J.str(s['inv_no'])], ' '),
    );
  }
}

String? _joinOrNull(List<String?> parts, String sep) {
  final kept = parts.whereType<String>().toList();
  return kept.isEmpty ? null : kept.join(sep);
}

/// A tester taking part in a session (a point of contact).
class Tester {
  const Tester(this.id, this.name, {this.designation});
  final int id;
  final String name;
  final String? designation;
}

/// The open testing session of a batch (`GET /batches/{id}/testing-session`).
class TestingSession {
  const TestingSession({
    required this.status,
    this.statusLabel,
    this.progress,
    this.testers = const [],
    this.allTested = false,
    this.current,
    this.samples = const [],
  });

  final String? status;
  final String? statusLabel;
  final double? progress;
  final List<Tester> testers;
  final bool allTested;
  final SampleResult? current;
  final List<SampleResult> samples;

  factory TestingSession.fromJson(Map<String, dynamic> j) {
    final session = J.map(j['session']) ?? const {};
    return TestingSession(
      status: J.str(session['status']),
      statusLabel: J.str(session['status_label']),
      progress: J.dbl(session['progress']),
      testers: [
        for (final t in (session['testers'] is List ? session['testers'] as List : const []).whereType<Map<String, dynamic>>())
          if (J.integer(t['id']) case final id?) Tester(id, J.str(t['name']) ?? '#$id', designation: J.str(t['designation'])),
      ],
      allTested: J.boolOr(j['all_tested'], false),
      current: J.map(j['current_sample']) == null ? null : SampleResult.fromJson(J.map(j['current_sample'])!),
      samples: [
        for (final s in (j['samples'] is List ? j['samples'] as List : const []).whereType<Map<String, dynamic>>())
          if (SampleResult.fromJson(s) case final r?) r,
      ],
    );
  }
}

/// A batch's testing results (`GET /batches/{id}/testing-results`).
class TestingResults {
  const TestingResults({this.statusLabel, this.progress, this.total, this.completed, this.averages = const {}, this.results = const []});
  final String? statusLabel;
  final double? progress;
  final int? total;
  final int? completed;

  /// Average score per letter: C, T, S, B.
  final Map<String, double> averages;
  final List<SampleResult> results;

  factory TestingResults.fromJson(Map<String, dynamic> j) {
    final session = J.map(j['session']) ?? const {};
    final stats = J.map(j['statistics']) ?? const {};
    return TestingResults(
      statusLabel: J.str(session['status_label']),
      progress: J.dbl(session['progress']),
      total: J.integer(stats['total_samples']),
      completed: J.integer(stats['completed_samples']),
      averages: {
        for (final l in const ['c', 't', 's', 'b'])
          if (J.dbl(stats['average_${l}_score']) case final v?) l.toUpperCase(): v,
      },
      results: [
        for (final r in (j['results'] is List ? j['results'] as List : const []).whereType<Map<String, dynamic>>())
          if (SampleResult.fromJson(r) case final x?) x,
      ],
    );
  }
}

/// Batch testing, status and export calls.
class BatchTestingRepository {
  const BatchTestingRepository(this._api);
  final Api _api;

  /// `PATCH /batches/{id}/status` (`status` from `form-options` → `batch_statuses`).
  Future<void> setStatus(int batchId, String status) => _api.patch('/batches/$batchId/status', {'status': status});

  /// Starts a session with these testers (point-of-contact ids).
  Future<void> initiate(int batchId, List<int> testers) => _api.post('/batches/$batchId/initiate-testing', {'testers': testers});

  /// The open session, or null when testing hasn't been started (404).
  Future<TestingSession?> session(int batchId) async {
    final data = await _api.lookup('/batches/$batchId/testing-session');
    return data == null ? null : TestingSession.fromJson(data);
  }

  /// Saves every tester's scores for the current sample. Returns whether
  /// another sample is waiting (`has_next`).
  Future<bool> saveScores(int batchId, List<TesterScore> scores, {String? remarks}) async {
    final body = await _api.postBody('/batches/$batchId/testing-session/scores', {
      'tester_results': [for (final s in scores) s.toJson()],
      if (remarks != null && remarks.isNotEmpty) 'sample_remarks': remarks,
    });
    return J.boolOr(body['has_next'], false);
  }

  Future<TestingResults?> results(int batchId) async {
    final data = await _api.lookup('/batches/$batchId/testing-results');
    return data == null ? null : TestingResults.fromJson(data);
  }

  /// Downloads a CSV export to a temporary file and returns its path:
  /// one batch's samples, or every batch when [batchId] is null.
  Future<String> export({int? batchId}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = batchId == null ? '${dir.path}/batches_$stamp.csv' : '${dir.path}/batch_${batchId}_samples_$stamp.csv';
    try {
      await _api.dio.download(batchId == null ? '/batches/export' : '/batches/$batchId/export-samples', path);
    } on DioException catch (e) {
      throw mapError(e);
    }
    if (!await File(path).exists()) throw const ServerFailure();
    return path;
  }
}

final batchTestingRepositoryProvider = Provider((ref) => BatchTestingRepository(ref.watch(apiProvider)));

final testingSessionProvider = FutureProvider.autoDispose.family<TestingSession?, int>(
  (ref, batchId) => ref.read(batchTestingRepositoryProvider).session(batchId),
);
final testingResultsProvider = FutureProvider.autoDispose.family<TestingResults?, int>(
  (ref, batchId) => ref.read(batchTestingRepositoryProvider).results(batchId),
);
