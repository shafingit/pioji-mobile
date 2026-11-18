import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/core/widgets/status_badge.dart';
import 'package:tea_erp/features/masters/data/form_options.dart';

void main() {
  // Shape of `GET /form-options` (two lists trimmed).
  final options = FormOptions.fromJson({
    'currencies': [
      {'value': 'INR', 'label': 'INR', 'default': true},
      {'value': 'USD', 'label': 'USD', 'default': false},
    ],
    'contract_statuses': [
      {'value': 'draft', 'label': 'In Negotiation'},
      {'value': 'active', 'label': 'Final'},
    ],
    'offices': [
      {'value': 4, 'label': 'Guwahati Office', 'city': 'Guwahati'},
    ],
  });

  test('labels come from the list, falling back to the value', () {
    expect(options.label('contract_statuses', 'active'), 'Final');
    expect(options.label('contract_statuses', 'expired'), 'expired');
    expect(options.label('contract_statuses', null), isNull);
  });

  test('the website default starts a new form, else the first option', () {
    expect(options.initial('currencies'), 'INR');
    expect(options.initial('contract_statuses'), 'draft');
    expect(options.initial('missing'), isNull);
  });

  test('numeric values become strings and keep their extra keys', () {
    final office = options['offices'].single;
    expect(office.value, '4');
    expect(office.extra['city'], 'Guwahati');
  });

  test('segments get an "All" entry first', () {
    expect(options.map('contract_statuses', all: 'All'), {'': 'All', 'draft': 'In Negotiation', 'active': 'Final'});
    expect(options.map('contract_statuses').containsKey(''), isFalse);
  });

  test('status tints', () {
    expect(statusTone('approved'), Tone.success);
    expect(statusTone('price_mismatch'), Tone.warning);
    expect(statusTone('rejected'), Tone.danger);
    expect(statusTone('draft'), Tone.neutral);
  });
}
