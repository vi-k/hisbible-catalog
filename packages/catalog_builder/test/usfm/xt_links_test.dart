import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  final books = RefBooks({'Мф': 470, 'Ин': 500, 'Быт': 10});

  List<MarkupNode> resolve(
    String text, {
    int book = 10,
    int chapter = 1,
    RefBooks? names,
    bool Function(RefRange place)? exists,
    XtStats? stats,
  }) => resolveXtLinks(
    [
      CrossrefLink(null, [TextRun(text)]),
    ],
    names ?? books,
    book: book,
    chapter: chapter,
    exists: exists,
    stats: stats,
  );

  test('a list of places becomes links, the rest stays text', () {
    final out = resolveXtLinks(
      [
        const CrossrefLink(null, [
          TextRun('Мф 1:1; 2:3-5; Ин 3:16, 18; см. выше'),
        ]),
      ],
      books,
      book: 10,
      chapter: 1,
    );
    expect(
      writeMarkup(out),
      '<x r="MAT.1.1">Мф 1:1</x>; <x r="MAT.2.3-MAT.2.5">2:3-5</x>; '
      '<x r="JHN.3.16">Ин 3:16</x>, <x r="JHN.3.18">18</x>; см. выше',
    );
  });

  test('a lone verse number without a book stays text', () {
    final out = resolveXtLinks(
      [
        const CrossrefLink(null, [TextRun('ст. 4')]),
      ],
      books,
      book: 10,
      chapter: 2,
    );
    expect(writeMarkup(out), 'ст. 4');
  });

  test('link-href wins over the text', () {
    final book = parseUsfm(
      r'\id MAT'
      '\n'
      r'\c 1'
      '\n'
      r'\v 1 Текст\x - \xo 1:1 \xt Быт 1:1|link-href="GEN 1:1"\xt*\x*',
    );
    final note = book.notes.single;
    expect(writeMarkup(note.nodes), contains('<x r="GEN.1.1">Быт 1:1</x>'));
  });

  test('a link-href range and a range across chapters', () {
    final book = parseUsfm(
      r'\id MAT'
      '\n'
      r'\c 1'
      '\n'
      r'\v 1 Текст\x - \xo 1:1 \xt Быт 1:1-3|link-href="GEN 1:1-3"\xt* '
      r'\xt Быт 2|link-href="GEN 2:1-3:4"\xt*\x*',
    );
    expect(
      writeMarkup(book.notes.single.nodes),
      '<x r="GEN.1.1-GEN.1.3">Быт 1:1-3</x> '
      '<x r="GEN.2.1-GEN.3.4">Быт 2</x>',
    );
  });

  test('an xt without link-href waits for the text parser', () {
    final book = parseUsfm(
      r'\id MAT'
      '\n'
      r'\c 1'
      '\n'
      r'\v 1 Текст\x - \xo 1:1 \xt Мф 1:1; 2:3\xt*\x*',
    );
    expect(book.notes.single.nodes, [
      const CrossrefLink(null, [TextRun('Мф 1:1; 2:3')]),
    ]);
  });

  test('a link-href that cannot be read is treated as absent', () {
    final book = parseUsfm(
      r'\id MAT'
      '\n'
      r'\c 1'
      '\n'
      r'\v 1 Текст\x - \xo 1:1 \xt Быт 1:1|link-href="nonsense"\xt*\x*',
    );
    expect(book.notes.single.nodes, [
      const CrossrefLink(null, [TextRun('Быт 1:1')]),
    ]);
  });

  test('book names match case-insensitively, without a final dot', () {
    final names = RefBooks({'1 Кор.': 530, 'Кор': 999, 'Ин.': 500});
    expect(names.book('1 кор'), 530);
    expect(names.book('ИН'), 500);
    expect(names.book('Нет'), isNull);
    expect(
      writeMarkup(resolve('1 Кор. 3:4; 1Кор 5:6; Ин.3:16', names: names)),
      '<x r="1CO.3.4">1 Кор. 3:4</x>; <x r="1CO.5.6">1Кор 5:6</x>; '
      '<x r="JHN.3.16">Ин.3:16</x>',
    );
  });

  test('the longest book name wins and the name must end at a word', () {
    final names = RefBooks({'Ин': 500, 'Иное': 10, 'Иов': 220});
    expect(
      writeMarkup(resolve('Иное 1:1; Иновато 2:2', names: names)),
      '<x r="GEN.1.1">Иное 1:1</x>; Иновато 2:2',
    );
  });

  test('RefBooks.of takes short, long names and the toc lines', () {
    final names = RefBooks.of([
      (
        number: 500,
        shortName: 'Ин',
        longName: 'От Иоанна',
        toc2: 'Иоанн',
        toc3: null,
      ),
    ]);
    expect(names.book('Ин'), 500);
    expect(names.book('от иоанна'), 500);
    expect(names.book('Иоанн'), 500);
  });

  test('a place missing from the book scheme stays text', () {
    final out = resolve(
      'Мф 1:1; Ин 3:99; Быт 1:1',
      exists: (place) => place.start.verse < 50 && place.start.book != 10,
    );
    expect(writeMarkup(out), '<x r="MAT.1.1">Мф 1:1</x>; Ин 3:99; Быт 1:1');
  });

  test('a range that ends before it starts stays text', () {
    expect(writeMarkup(resolve('Мф 1:5-3')), '<x r="MAT.1.5">Мф 1:5</x>-3');
  });

  test('a verse list takes its book and chapter from the last place', () {
    expect(
      writeMarkup(resolve('Ин 3:16-18, 20, 4:1')),
      '<x r="JHN.3.16-JHN.3.18">Ин 3:16-18</x>, '
      '<x r="JHN.3.20">20</x>, <x r="JHN.4.1">4:1</x>',
    );
  });

  test('a book inside a list switches the book', () {
    expect(
      writeMarkup(resolve('Мф 1:1, Ин 2:2')),
      '<x r="MAT.1.1">Мф 1:1</x>, <x r="JHN.2.2">Ин 2:2</x>',
    );
  });

  test('en dash, em dash and a verse letter are accepted', () {
    expect(
      writeMarkup(resolve('Мф 1:1–3; Ин 2:4—5; Быт 3:6а')),
      '<x r="MAT.1.1-MAT.1.3">Мф 1:1–3</x>; '
      '<x r="JHN.2.4-JHN.2.5">Ин 2:4—5</x>; <x r="GEN.3.6">Быт 3:6а</x>',
    );
  });

  test('a range into another chapter', () {
    expect(
      writeMarkup(resolve('Мф 1:20-2:3')),
      '<x r="MAT.1.20-MAT.2.3">Мф 1:20-2:3</x>',
    );
  });

  test('the book is not carried from one xt to the next', () {
    final out = resolveXtLinks(
      [
        const CrossrefLink(null, [TextRun('Мф 1:1')]),
        const TextRun(' '),
        const CrossrefLink(null, [TextRun('Ин 3:16')]),
      ],
      books,
      book: 10,
      chapter: 1,
    );
    expect(
      writeMarkup(out),
      '<x r="MAT.1.1">Мф 1:1</x> <x r="JHN.3.16">Ин 3:16</x>',
    );
  });

  test('links with a target are kept, the rest of the tree is walked', () {
    final target = RefRange.parse('GEN.1.1')!;
    final out = resolveXtLinks(
      [
        CrossrefLink(target, const [TextRun('Быт 1:1')]),
        const StyledSpan(MarkupStyle.emphasis, [
          CrossrefLink(null, [TextRun('Мф 2:2')]),
        ]),
        const FootnoteRef(1, 'a'),
      ],
      books,
      book: 10,
      chapter: 1,
    );
    expect(
      writeMarkup(out),
      [
        '<x r="GEN.1.1">Быт 1:1</x>',
        '<em><x r="MAT.2.2">Мф 2:2</x></em>',
        '<f id="1" c="a"/>',
      ].join(),
    );
  });

  test('stats count links by href, by text and unresolved', () {
    final stats = XtStats();
    resolveXtLinks(
      [
        CrossrefLink(RefRange.parse('GEN.1.1'), const [TextRun('Быт 1:1')]),
        const CrossrefLink(null, [TextRun('Мф 1:1')]),
        const CrossrefLink(null, [TextRun('см. выше')]),
      ],
      books,
      book: 10,
      chapter: 1,
      stats: stats,
    );
    expect((stats.linked, stats.byHref, stats.unresolved), (2, 1, 1));
  });
}
