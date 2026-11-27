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

  test('a bare value after the bar is the default link-href', () {
    final book = parseUsfm(
      r'\id MAT'
      '\n'
      r'\c 1'
      '\n'
      r'\v 1 Текст\x - \xo 1:1 \xt Быт 1:1|GEN 1:1\xt*\x*',
    );
    expect(writeMarkup(book.notes.single.nodes), '<x r="GEN.1.1">Быт 1:1</x>');
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

  test('a range that ends before it starts stays text as a whole', () {
    expect(
      writeMarkup(resolve('Мф 1:5-3; Ин 3:16')),
      'Мф 1:5-3; <x r="JHN.3.16">Ин 3:16</x>',
    );
  });

  test('a range end outside the scheme makes the whole place text', () {
    expect(
      writeMarkup(
        resolve('Мф 1:5-9', exists: (place) => (place.end?.verse ?? 0) < 9),
      ),
      'Мф 1:5-9',
    );
  });

  test('a comma verse before a lowercase word is still a verse', () {
    // `18` и `5` — стихи; ` и 20` и ` см.` остаются текстом, а `20` после
    // «и» не список, так что текстом остаётся и он.
    expect(
      writeMarkup(resolve('Ин 3:16, 18 и 20')),
      '<x r="JHN.3.16">Ин 3:16</x>, <x r="JHN.3.18">18</x> и 20',
    );
    expect(
      writeMarkup(resolve('Мф 5:3, 5 см.')),
      '<x r="MAT.5.3">Мф 5:3</x>, <x r="MAT.5.5">5</x> см.',
    );
  });

  test('a comma verse before a book name is not a verse', () {
    expect(
      writeMarkup(resolve('Мф 1:1, 2 Кор 3:4')),
      '<x r="MAT.1.1">Мф 1:1</x>, 2 Кор 3:4',
    );
  });

  test('a comma verse before a word is the start of a book name', () {
    final names = RefBooks({'1 Kings': 110, '2 Kings': 120});
    expect(
      writeMarkup(resolve('1 Kings 17:1, 2 Kings 2:1', names: names)),
      '<x r="1KI.17.1">1 Kings 17:1</x>, <x r="2KI.2.1">2 Kings 2:1</x>',
    );
    // Название второй книги неизвестно: `2` не стих первой.
    final one = RefBooks({'1 Kings': 110});
    expect(
      writeMarkup(resolve('1 Kings 17:1, 2 Kings 2:1', names: one)),
      '<x r="1KI.17.1">1 Kings 17:1</x>, 2 Kings 2:1',
    );
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

  test('a line of parallel places in brackets with dots and hyphens', () {
    expect(
      writeMarkup(resolve('(Мф 26.26-29; Ин 3:1‑8, 4.2–5.3)')),
      '(<x r="MAT.26.26-MAT.26.29">Мф 26.26-29</x>; '
      '<x r="JHN.3.1-JHN.3.8">Ин 3:1‑8</x>, '
      '<x r="JHN.4.2-JHN.5.3">4.2–5.3</x>)',
    );
    expect(
      writeMarkup(resolve('[Быт 1:1]; (2.3)')),
      '[<x r="GEN.1.1">Быт 1:1</x>]; (<x r="GEN.2.3">2.3</x>)',
    );
  });

  test('a verse after a comma is not the chapter of a dotted place', () {
    expect(
      writeMarkup(resolve('Ин 3:16, 4.2')),
      '<x r="JHN.3.16">Ин 3:16</x>, <x r="JHN.4.2">4.2</x>',
    );
  });

  group('a place after an unknown book name', () {
    final names = RefBooks({'Matt': 470, 'Luk': 490, 'Sal': 230, 'Lev': 30});
    String out(String text, int book) =>
        writeMarkup(resolve(text, book: book, names: names));

    test('an unknown name takes no link for the places after it', () {
      expect(
        out('Daniel 9:27; 11:31; 12:11', 470),
        'Daniel 9:27; 11:31; 12:11',
      );
      expect(
        out('Sal. 33.6. Giov. 1.1-3. Ebr. 1.10; 11.3', 500),
        '<x r="PSA.33.6">Sal. 33.6</x>. Giov. 1.1-3. Ebr. 1.10; 11.3',
      );
      expect(
        out('Matt 12:18; 17:5; Isa 42:1; 1:11', 470),
        '<x r="MAT.12.18">Matt 12:18</x>; <x r="MAT.17.5">17:5</x>; '
        'Isa 42:1; 1:11',
      );
    });

    test('a multi-word, hyphened or caseless unknown name counts too', () {
      expect(out('Pa je 65.8; 89.10', 470), 'Pa je 65.8; 89.10');
      expect(out("E'sotas 20:12; 21:17", 470), "E'sotas 20:12; 21:17");
      expect(out('Heti-heun 18:16; 20:21', 490), 'Heti-heun 18:16; 20:21');
      expect(out('S.K. 2.1-3; 3.5-6', 230), 'S.K. 2.1-3; 3.5-6');
      expect(out('उत्पत्ती 12:3; 18:18', 510), 'उत्पत्ती 12:3; 18:18');
    });

    test('a lowercase word before a number does not stop the link', () {
      expect(
        out('Lev. cap. 3; 22.18,21', 30),
        'Lev. cap. 3; <x r="LEV.22.18">22.18</x>,<x r="LEV.22.21">21</x>',
      );
      expect(out('см. 3:16; 4:2', 500), 'см. 3:16; <x r="JHN.4.2">4:2</x>');
    });
  });
}
