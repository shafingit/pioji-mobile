import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/core/storage/current_branch.dart';

/// Runs [applyBranch] and returns what the request ends up with.
({Map<String, dynamic> query, Map<String, dynamic> headers, Object? body}) run(String method, String path, {Map<String, dynamic> query = const {}, Object? body}) {
  var q = query;
  final headers = <String, dynamic>{};
  Object? b = body;
  applyBranch(
    method: method,
    path: path,
    query: q,
    headers: headers,
    body: body,
    branchId: 4,
    setQuery: (v) => q = v,
    setBody: (v) => b = v,
  );
  return (query: q, headers: headers, body: b);
}

void main() {
  test('list reads carry branch_id, keeping the other filters', () {
    final r = run('GET', '/offer-lists', query: const {'page': 1});
    expect(r.query, {'page': 1, 'branch_id': 4});
    expect(r.headers['X-Branch-Id'], '4');
  });

  test('new records carry branch_id; a branch the form set wins', () {
    expect(run('POST', '/offer-lists', body: {'inv_no': '1'}).body, {'branch_id': 4, 'inv_no': '1'});
    expect(run('POST', '/samples/transfer', body: {'branch_id': 2}).body, {'branch_id': 2});
  });

  test('uploads with a file carry branch_id as a form field', () {
    final form = FormData.fromMap({'courier_name': 'X'});
    run('POST', '/courier-entries', body: form);
    expect(form.fields.where((f) => f.key == 'branch_id').map((f) => f.value), ['4']);
    final set = FormData.fromMap({'branch_id': '2'});
    run('POST', '/samples/bulk-upload', body: set);
    expect(set.fields.where((f) => f.key == 'branch_id').map((f) => f.value), ['2']);
  });

  test('company-wide records get no branch', () {
    expect(run('POST', '/buyers', body: {'buyer_name': 'A'}).body, {'buyer_name': 'A'});
    expect(run('POST', '/sellers', body: {'seller_name': 'B'}).body, {'seller_name': 'B'});
    expect(run('POST', '/users', body: {'name': 'C'}).body, {'name': 'C'});
    expect(run('POST', '/samples', body: {'x': 1}).body, {'branch_id': 4, 'x': 1});
  });

  test('edits and sign-in are left alone', () {
    expect(run('PUT', '/offer-lists/5', body: {'inv_no': '1'}).body, {'inv_no': '1'});
    expect(run('POST', '/offer-lists/5', body: {'_method': 'PUT'}).body, {'_method': 'PUT'});
    final login = run('POST', '/auth/login', body: {'email': 'x'});
    expect(login.body, {'email': 'x'});
    expect(login.headers, isEmpty);
  });
}
