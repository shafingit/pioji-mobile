import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/core/errors/app_failure.dart';

void main() {
  test('plain server sentences are shown', () {
    expect(const ServerFailure(500, 'No unbatched samples found for 2026-11-20').message, 'No unbatched samples found for 2026-11-20');
  });

  test('technical or empty messages fall back to the generic text', () {
    const generic = 'Something went wrong on our side. Try again.';
    for (final m in [
      null,
      '',
      'Server Error',
      'SQLSTATE[42S22]: Column not found: 1054 Unknown column',
      'Call to a member function format() on null',
      'Undefined array key "date"',
      'Database error, try again',
      'line one\nline two',
    ]) {
      expect(ServerFailure(500, m).message, generic, reason: '$m');
    }
  });
}
