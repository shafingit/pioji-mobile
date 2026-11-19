import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/features/batches/data/batch_testing.dart';

void main() {
  // Shapes seen on staging, 19 Nov 2026 (trimmed).
  test('testing session: testers and the current sample', () {
    final s = TestingSession.fromJson({
      'session': {
        'status': 'initiated',
        'status_label': 'Initiated',
        'progress': 0,
        'testers': [
          {'id': 98, 'name': 'ANUP YADAV', 'designation': null},
          {'id': 104, 'name': 'Bhargav', 'designation': 'SR. QA Tester'},
        ],
      },
      'all_tested': false,
      'current_sample': {
        'sample_result_id': 64,
        'sample_sequence': 1,
        'status': 'pending',
        'tester_results': [],
        'sample': {'id': 84, 'sample_id': 'SMP2026110032', 'garden_name': 'SANSAAR', 'grade': {'code': 'BOP'}, 'invoice_prefix': {'code': 'S'}, 'inv_no': '99777'},
      },
      'samples': [
        {'sample_result_id': 64, 'sample_sequence': 1, 'sample_id': 84, 'sample_code': 'SMP2026110032', 'status': 'pending'},
      ],
    });
    expect(s.testers.map((t) => t.id), [98, 104]);
    expect(s.current!.id, 64);
    expect(s.current!.title, 'SANSAAR · BOP');
    expect(s.current!.invoice, 'S 99777');
    expect(s.samples.single.sampleId, 84);
    expect(s.allTested, isFalse);
  });

  test('results: averages and string scores', () {
    final r = TestingResults.fromJson({
      'session': {'status_label': 'Completed', 'progress': 72.7},
      'statistics': {'total_samples': 11, 'completed_samples': 8, 'average_c_score': 50.36, 'average_t_score': 49.27, 'average_s_score': 50.36, 'average_b_score': 6.18},
      'results': [
        {
          'sample_result_id': 53,
          'status': 'completed',
          'tester_results': [
            {'tester_id': '97', 'c_score': '70', 't_score': '68', 's_score': '70', 'b_score': '0', 'remarks': 'NORMAL'},
          ],
          'average_score_result': '70-68-70-0',
          'overall_average': 52,
          'sample': {'id': 64, 'garden_name': 'GELAKEY', 'grade': {'code': 'BOPSM'}},
        },
      ],
    });
    expect(r.completed, 8);
    expect(r.averages.keys, ['C', 'T', 'S', 'B']);
    final x = r.results.single;
    expect(x.done, isTrue);
    expect(x.scores.single.testerId, 97);
    expect(x.scores.single.t, 68);
    expect(x.average, '70-68-70-0');
  });

  test('scores are sent as the API expects', () {
    const s = TesterScore(testerId: 98, c: 60, t: 55, s: 50, b: 45);
    expect(s.toJson(), {'tester_id': 98, 'c_score': 60.0, 't_score': 55.0, 's_score': 50.0, 'b_score': 45.0});
  });
}
