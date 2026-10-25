import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

VerseRef r(int b, int c, int v) => VerseRef(b, c, v);

final vs = Versification.standard;

void mapsTo(
  VerseScheme s,
  Map<VerseRef, VerseRef> toCanonical, [
  Map<VerseRef, VerseRef> fromCanonical = const {},
]) {
  toCanonical.forEach(
    (a, b) => expect(vs.toCanonical(a, s), b, reason: '$s $a'),
  );
  fromCanonical.forEach(
    (a, b) => expect(vs.fromCanonical(a, s), b, reason: '$s $a'),
  );
}

void main() {
  test('russian synodal, full edition', () {
    mapsTo(
      VerseScheme.rso,
      {
        r(230, 3, 1): r(230, 3, 0),
        r(230, 9, 22): r(230, 10, 0),
        r(230, 9, 23): r(230, 10, 2),
        r(230, 9, 39): r(230, 10, 18),
        r(230, 22, 1): r(230, 23, 1),
        r(230, 113, 9): r(230, 115, 0),
        r(230, 115, 1): r(230, 116, 11),
        r(230, 151, 1): r(230, 151, 1),
        r(520, 14, 24): r(520, 16, 25),
        r(340, 3, 24): r(323, 1, 1),
        r(340, 3, 91): r(340, 3, 24),
        r(340, 3, 100): r(340, 4, 3),
        r(340, 4, 1): r(340, 4, 4),
        r(340, 13, 1): r(325, 1, 1),
        r(340, 14, 42): r(345, 1, 42),
        r(40, 13, 1): r(40, 12, 16),
        r(220, 40, 20): r(220, 41, 1),
        r(260, 7, 1): r(260, 6, 13),
        r(730, 13, 1): r(730, 12, 18),
        r(10, 1, 1): r(10, 1, 1),
        r(500, 3, 16): r(500, 3, 16),
        r(145, 1, 1): r(145, 1, 1),
        r(140, 36, 23): r(140, 36, 23),
        r(230, 114, 8): r(230, 116, 8),
      },
      {
        r(230, 10, 1): r(230, 9, 22),
        r(230, 11, 1): r(230, 10, 1),
        r(520, 16, 25): r(520, 14, 24),
        r(340, 3, 24): r(340, 3, 91),
        r(323, 1, 1): r(340, 3, 24),
        r(325, 1, 1): r(340, 13, 1),
        r(345, 1, 1): r(340, 14, 1),
        r(220, 41, 1): r(220, 40, 20),
        r(260, 6, 13): r(260, 7, 1),
        r(320, 6, 1): r(315, 1, 1),
      },
    );
  });

  test('russian synodal, canonical edition', () {
    mapsTo(
      VerseScheme.rsc,
      {
        r(230, 9, 22): r(230, 10, 0),
        r(230, 22, 1): r(230, 23, 1),
        r(230, 114, 9): r(230, 116, 9),
        r(230, 115, 1): r(230, 116, 10),
        r(520, 14, 24): r(520, 16, 25),
        r(340, 3, 33): r(340, 4, 3),
      },
      {
        r(230, 116, 10): r(230, 115, 1),
        r(230, 116, 11): r(230, 115, 2),
        r(230, 23, 1): r(230, 22, 1),
      },
    );
    expect(vs.toCanonical(r(340, 3, 33), VerseScheme.rso), r(323, 1, 10));
  });

  test('hebrew numbering, title is verse 1', () {
    mapsTo(
      VerseScheme.org,
      {
        r(230, 3, 1): r(230, 3, 0),
        r(230, 3, 2): r(230, 3, 1),
        r(230, 51, 3): r(230, 51, 1),
        r(360, 3, 1): r(360, 2, 28),
        r(360, 4, 1): r(360, 3, 1),
        r(460, 3, 19): r(460, 4, 1),
        r(10, 32, 1): r(10, 31, 55),
        r(340, 3, 31): r(340, 4, 1),
        r(340, 4, 1): r(340, 4, 4),
        r(290, 8, 23): r(290, 9, 1),
        r(470, 1, 1): r(470, 1, 1),
      },
      {
        r(230, 3, 0): r(230, 3, 1),
        r(230, 51, 1): r(230, 51, 3),
        r(360, 2, 28): r(360, 3, 1),
        r(460, 4, 6): r(460, 3, 24),
        r(10, 31, 55): r(10, 32, 1),
        r(290, 9, 2): r(290, 9, 1),
      },
    );
  });

  test('eng is the canonical scheme', () {
    expect(vs.toCanonical(r(230, 9, 22), VerseScheme.eng), r(230, 9, 22));
    expect(vs.fromCanonical(r(230, 10, 1), VerseScheme.eng), r(230, 10, 1));
  });

  test('vrs lines pair verses, drop letters and skip foreign books', () {
    final v = Versification.fromVrs({
      VerseScheme.eng: '''
GEN 1:3 2:5 3:1
GEN 2:5 = GEN 3:1
''',
      VerseScheme.rso: '''
# комментарий = не соответствие
PSA 3:9 4:2
PSA 3:1-3 = PSA 3:0-1  # лишний стих идёт к последнему
PSA 4:0 = PSA 5:10
PSA 4:1 = PSA 5:10
PSA 6:5a-6b = PSA 6:7
PSA 7:1 = ESG 1:1
PSA 7:2 = PS2 1:1
EZA 1:1 = PSA 7:3
2CH 36:24 = MAN 1:1
SUS 1:2 = DAG 13:2
BEL 1:3 = DAG 14:3
2CH 2:1 = 2CH 1:18
''',
    });
    expect(v.toCanonical(r(230, 3, 1), VerseScheme.rso), r(230, 3, 0));
    expect(v.toCanonical(r(230, 3, 3), VerseScheme.rso), r(230, 3, 1));
    expect(v.fromCanonical(r(230, 3, 1), VerseScheme.rso), r(230, 3, 2));
    // Источник со стихом 0 уступает источнику с ненулевым стихом.
    expect(v.fromCanonical(r(230, 5, 10), VerseScheme.rso), r(230, 4, 1));
    expect(v.toCanonical(r(230, 6, 6), VerseScheme.rso), r(230, 6, 7));
    expect(v.toCanonical(r(230, 7, 1), VerseScheme.rso), r(230, 7, 1));
    expect(v.toCanonical(r(230, 7, 2), VerseScheme.rso), r(230, 7, 2));
    expect(v.fromCanonical(r(230, 7, 3), VerseScheme.rso), r(230, 7, 3));
    expect(v.toCanonical(r(140, 36, 24), VerseScheme.rso), r(140, 36, 24));
    expect(v.toCanonical(r(325, 1, 2), VerseScheme.rso), r(325, 1, 2));
    expect(v.toCanonical(r(345, 1, 3), VerseScheme.rso), r(345, 1, 3));
    // Пара книг отбрасывается, только если книги разные.
    expect(v.toCanonical(r(140, 2, 1), VerseScheme.rso), r(140, 1, 18));
    // Каноническая сторона идёт через соответствия eng.
    expect(v.toCanonical(r(10, 3, 1), VerseScheme.rso), r(10, 2, 5));
    expect(v.fromCanonical(r(10, 2, 5), VerseScheme.rso), r(10, 3, 1));
    // Книга без кода SIL переводится в себя.
    expect(v.toCanonical(r(192, 1, 1), VerseScheme.rso), r(192, 1, 1));
    expect(v.lastVerses(VerseScheme.rso, 230), {3: 9, 4: 2});
    expect(v.lastVerses(VerseScheme.eng, 10), {1: 3, 2: 5, 3: 1});
    expect(v.lastVerses(VerseScheme.org, 10), isEmpty);
    expect(v.lastVerses(VerseScheme.eng, 192), isEmpty);
  });

  test('same-book lines of 2 Chronicles are kept', () {
    mapsTo(
      VerseScheme.org,
      {
        r(140, 1, 18): r(140, 2, 1),
        r(140, 2, 17): r(140, 2, 18),
        r(140, 13, 23): r(140, 14, 1),
        r(140, 14, 1): r(140, 14, 2),
      },
      {r(140, 2, 1): r(140, 1, 18), r(140, 14, 1): r(140, 13, 23)},
    );
    // Строки 2CH ↔ MAN по-прежнему отброшены: Молитва Манассии — книга 145.
    mapsTo(
      VerseScheme.rso,
      {r(140, 37, 1): r(140, 37, 1)},
      {r(145, 1, 1): r(145, 1, 1)},
    );
  });

  test('malformed vrs lines name the line', () {
    for (final bad in ['GEN 1:31 2', 'GEN 1:x', 'GEN 1:2:3', 'GEN 1:2 = EXO']) {
      expect(
        () => Versification.fromVrs({VerseScheme.eng: bad}),
        throwsA(isA<FormatException>().having((e) => e.source, 'source', bad)),
        reason: bad,
      );
    }
  });

  test('verse refs compare by value', () {
    expect(r(10, 1, 1), r(10, 1, 1));
    expect(r(10, 1, 1).hashCode, r(10, 1, 1).hashCode);
    expect(r(10, 1, 1), isNot(r(10, 1, 2)));
  });
}
