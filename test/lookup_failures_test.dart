import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/core/application/lookup_retry.dart';
import 'package:tea_erp/core/errors/app_failure.dart';
import 'package:tea_erp/core/network/api.dart';
import 'package:tea_erp/features/masters/data/masters_repository.dart';

/// Answers `GET /grades?page=n` from [pages]; a page listed in [failures]
/// answers 500 that many times first.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.pages, {Map<int, int> failures = const {}}) : _failures = Map.of(failures);
  final List<List<String>> pages;
  final Map<int, int> _failures;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    final page = int.parse('${options.queryParameters['page'] ?? 1}');
    final headers = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if ((_failures[page] ?? 0) > 0) {
      _failures[page] = _failures[page]! - 1;
      return ResponseBody.fromString(jsonEncode({'success': false, 'message': 'Database error'}), 500, headers: headers);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {
          'grades': [for (final g in pages[page - 1]) {'grade_name': g}],
          'pagination': {'current_page': page, 'last_page': pages.length},
        },
      }),
      200,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

MastersRepository _repo(_FakeServer server) =>
    MastersRepository(Api(Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server));

void main() {
  test('a page that fails once is tried again', () async {
    final server = _FakeServer([['BP'], ['PF']], failures: {2: 1});
    expect(await _repo(server).grades(), ['BP', 'PF']);
  });

  test('a page that keeps failing is skipped; the rest are kept', () async {
    final server = _FakeServer([['BP'], ['PF'], ['D']], failures: {2: 5});
    expect(await _repo(server).grades(), ['BP', 'D']);
  });

  test('nothing loading is an error, not an empty list', () async {
    final server = _FakeServer([['BP']], failures: {1: 5});
    await expectLater(_repo(server).grades(), throwsA(isA<AppFailure>()));
  });

  test('dropdown lists retry 3 times, except failures a retry cannot fix', () {
    const failure = ServerFailure(500);
    expect(lookupRetry(0, failure), const Duration(seconds: 1));
    expect(lookupRetry(2, failure), const Duration(seconds: 4));
    expect(lookupRetry(3, failure), isNull);
    expect(lookupRetry(0, const ForbiddenFailure()), isNull);
    expect(lookupRetry(0, const UnauthorizedFailure()), isNull);
  });
}
