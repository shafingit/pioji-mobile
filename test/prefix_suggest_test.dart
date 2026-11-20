import 'package:flutter_test/flutter_test.dart';
import 'package:tea_erp/features/masters/data/masters_repository.dart';

void main() {
  // Shapes from staging, 20 Nov 2026: most gardens list E, C, D for every
  // grade; the master lists say which types each grade and prefix are for.
  const links = TypeLinks(
    grades: {
      'BP': {'brokens'},
      'PD': {'dust'},
      'PF': {'fannings'},
    },
    prefixes: {
      'C': {'General', 'brokens', 'fannings'},
      'D': {'General', 'brokens', 'dust'},
      'S': {'brokens', 'dust', 'fannings'},
    },
    standard: {'brokens', 'fannings', 'dust', 'whole'},
    labels: {'brokens': 'Brokens', 'fannings': 'Fannings', 'dust': 'Dust', 'ctc': 'Ctc'},
  );
  const ecd = ['E', 'C', 'D'];

  test('a single prefix is always picked', () {
    expect(suggestPrefix(prefixes: const ['S'], grade: null, links: TypeLinks.empty, recent: const {}), 'S');
  });

  test('the grade type leaves one prefix: dust → D, fannings → C', () {
    expect(suggestPrefix(prefixes: ecd, grade: 'PD', links: links, recent: const {}), 'D');
    expect(suggestPrefix(prefixes: ecd, grade: 'pf', links: links, recent: const {}), 'C');
  });

  test('brokens fit C and D: the garden history decides, else nothing', () {
    expect(suggestPrefix(prefixes: ecd, grade: 'BP', links: links, recent: const {}), isNull);
    expect(suggestPrefix(prefixes: ecd, grade: 'BP', links: links, recent: const {'BP': 'C'}), 'C');
    // History that doesn't fit the grade's type is ignored.
    expect(suggestPrefix(prefixes: ecd, grade: 'BP', links: links, recent: const {'BP': 'E'}), isNull);
  });

  test('no grade, no suggestion; unknown grade falls back to history', () {
    expect(suggestPrefix(prefixes: ecd, grade: null, links: links, recent: const {}), isNull);
    expect(suggestPrefix(prefixes: ecd, grade: 'XYZ', links: links, recent: const {'XYZ': 'E'}), 'E');
  });

  test('a prefix narrows the grades to its types', () {
    expect(links.gradeFitsPrefix('PD', 'D'), isTrue);
    expect(links.gradeFitsPrefix('PF', 'D'), isFalse);
    expect(links.gradeFitsPrefix('BP', 'C'), isTrue);
    expect(links.gradeFitsPrefix('UNKNOWN', 'C'), isTrue);
  });

  test('prefix · type choices: the default "ctc" set-up is split by type', () {
    String show(List<({String prefix, String type})> l) => l.map((x) => '${x.prefix}·${x.type}').join(' ');
    expect(show(links.pairs(const {'ctc': ['E', 'C', 'D']})), 'E·ctc C·brokens C·fannings D·brokens D·dust');
    // A garden set up by type keeps its own pairs.
    expect(show(links.pairs(const {'brokens': ['S'], 'fannings': ['S'], 'dust': ['S']})), 'S·brokens S·fannings S·dust');
  });

  test("a grade's own type", () {
    expect(links.gradeType('pd'), 'dust');
    expect(links.gradeType('UNKNOWN'), isNull);
  });

  test("a grade's real types: the master list first, else the garden's", () {
    expect(links.effectiveTypes('BP', 'ctc'), {'brokens'});
    expect(links.effectiveTypes('NEWGRADE', 'ctc'), {'ctc'});
    expect(links.effectiveTypes('NEWGRADE'), isEmpty);
  });
}
