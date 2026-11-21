import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/features/offer_lists/data/offer_lists_repository.dart';

void main() {
  test('the tasting sheet has only the tasting column, one row per offer', () {
    expect(tastingSheet([5275, 5281]), 'item_type,item_ref,mark_for_tasting\noffer_list,5275,1\noffer_list,5281,1');
    expect(tastingSheet([7]), 'item_type,item_ref,mark_for_tasting\noffer_list,7,1');
  });

  test('tastingMark reads the API flag', () {
    expect(OfferList.fromJson({'id': 1, 'tasting_mark': true}).tastingMark, isTrue);
    expect(OfferList.fromJson({'id': 2, 'tasting_mark': false}).tastingMark, isFalse);
    expect(OfferList.fromJson({'id': 3}).tastingMark, isFalse);
  });
}
