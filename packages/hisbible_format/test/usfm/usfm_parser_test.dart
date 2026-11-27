import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('psalm verse with Strong, styles and a note', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 3\n\\d A Psalm of David.\n'
      r'\v 1 \nd \+w LORD|strong="H3068"\+w*\nd*, how \add are\add* '
      r'they\f + \fr 3.1 \ft note\f*',
    );
    expect(book.verses.single.nodes, [
      const StyledSpan(MarkupStyle.divineName, [
        TaggedWord([TextRun('LORD')], strong: ['H3068']),
      ]),
      const TextRun(', how '),
      const StyledSpan(MarkupStyle.added, [TextRun('are')]),
      const TextRun(' they'),
      const FootnoteRef(1, 'a'),
    ]);
    expect(book.headings.single.kind, HeadingKind.title);
    expect(plainText(book.notes.single.nodes), 'note');
  });

  test('paragraph and words of Christ', () {
    final v = parseUsfm(
      '\\id JHN\n\\c 1\n\\v 1 One\n\\p\n'
      r'\v 2 \wj ¶ \+w Two|strong="G1"\+w*\wj*',
    ).verses[1];
    expect(v.nodes, [
      const ParagraphBreak(),
      const StyledSpan(MarkupStyle.wordsOfChrist, [
        TaggedWord([TextRun('Two')], strong: ['G1']),
      ]),
    ]);
  });

  test('poetry lines', () {
    final v = parseUsfm('\\id PSA\n\\c 1\n\\q1\n\\v 1 Line one\n\\q2 line two')
        .verses
        .single;
    expect(v.nodes, [
      const LineBreak(indent: 1),
      const TextRun('Line one'),
      const LineBreak(indent: 2),
      const TextRun('line two'),
    ]);
  });

  test('tolerates usfm oddities', () {
    final book = parseUsfm(
      '\\id JOB\n\\ip Intro\n\\c 42\n\\v 16-17 и умер Иов\n'
      '\\v 18\n\\zz odd\\zz* \\x - \\xo 42.1 \\xt Иак 5:11\\x*\n'
      '\\s Примечания\n\\p В Славянской Библии',
    );
    expect(book.verses.first.verseEnd, 17);
    expect(plainText(book.verses.first.nodes), 'и умер Иов');
    expect(book.verses[1].verse, 18);
    expect(book.unknownMarkers, contains('zz'));
    expect(book.notes.single.caller, '');
    expect(book.headings, isEmpty);
    expect(book.droppedFragments, greaterThan(0));
  });

  test('book fields and header markers', () {
    final book = parseUsfm(
      '\\id GEN Genesis, test\n\\usfm 3.0\n\\ide UTF-8\n\\rem note\n'
      '\\h Genesis \n\\toc1 The First Book of Moses\n\\toc2 Genesis\n'
      '\\toc3 Gen\n\\mt1 The First Book\n\\cl Chapter\n\\is1 Intro\n'
      '\\ip Some \\it intro\\it* text\n\\c 1\n\\cl Глава 1\n\\v 1 In',
    );
    expect(book.code, 'GEN');
    expect(book.header, 'Genesis');
    expect(book.toc1, 'The First Book of Moses');
    expect(book.toc2, 'Genesis');
    expect(book.toc3, 'Gen');
    expect(book.chapterLabel, 'Chapter');
    expect(book.verses.single.nodes, [const TextRun('In')]);
    expect(book.droppedFragments, 0);
    expect(book.unknownMarkers, isEmpty);
  });

  test('parts in a row are two pieces and chapters number verses anew', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\v 1a first\n\\v 1b second\n\\v 2 two\n'
      '\\c 2\n\\v 1 again',
    );
    expect(
      [for (final v in book.verses) (v.chapter, v.verse, v.part)],
      [(1, 1, 'a'), (1, 1, 'b'), (1, 2, ''), (2, 1, '')],
    );
    expect(book.verses[0].nodes, [const TextRun('first')]);
    expect(book.verses[1].nodes, [const TextRun('second')]);
    expect(book.verses.first.verseEnd, isNull);
  });

  test('Zechariah 4 keeps its pieces', () {
    final book = parseUsfm(
      '\\id ZEC\n\\c 4\n\\p\n\\v 5 alpha\n\\v 6a beta\n'
      '\\v 10b-14 gamma\n\\v 6b-10a delta\n',
    );
    expect(
      [
        for (final v in book.verses)
          (v.verse, v.part, v.verseEnd, v.partEnd, plainText(v.nodes)),
      ],
      [
        (5, '', null, '', 'alpha'),
        (6, 'a', null, '', 'beta'),
        (10, 'b', 14, '', 'gamma'),
        (6, 'b', 10, 'a', 'delta'),
      ],
    );
  });

  test('a moved verse stays where it stands', () {
    final book = parseUsfm(
      '\\id JOB\n\\c 3\n\\p\n\\v 16 alpha\n\\v 13 beta\n\\v 14 gamma\n',
    );
    expect([for (final v in book.verses) v.verse], [16, 13, 14]);
  });

  test('a capital part letter reads as a small one', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\p\n\\v 1 alpha\n\\v 1A beta\n'
      '\\v 2-6Б gamma\n\\v 6В delta\n',
    );
    expect(
      [for (final v in book.verses) (v.verse, v.part, v.verseEnd, v.partEnd)],
      [
        (1, '', null, ''),
        (1, 'a', null, ''),
        (2, '', 6, 'б'),
        (6, 'в', null, ''),
      ],
    );
  });

  test('an adjacent repeat joins its piece', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\p\n\\v 3 alpha\n\\v 3 beta\n\\v 4 gamma\n'
      '\\v 3 delta\n',
    );
    expect(
      [for (final v in book.verses) (v.verse, plainText(v.nodes))],
      [(3, 'alpha beta'), (4, 'gamma'), (3, 'delta')],
    );
  });

  test('Cyrillic parts', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\p\n\\v 1-6а альфа\n\\v 6б-11 бета\n',
    );
    expect(
      [for (final v in book.verses) (v.verse, v.part, v.verseEnd, v.partEnd)],
      [(1, '', 6, 'а'), (6, 'б', 11, '')],
    );
  });

  test('the end part of a piece in one verse is dropped', () {
    final verse = parseUsfm('\\id GEN\n\\c 1\n\\p\n\\v 5a-5b alpha\n')
        .verses
        .single;
    expect(
      (verse.verse, verse.part, verse.verseEnd, verse.partEnd),
      (5, 'a', null, ''),
    );
  });

  test('a heading belongs to its piece', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 2\n\\p\n\\v 4a alpha\n\\s Heading\n\\p\n'
      '\\v 4b beta\n\\v 5 gamma\n',
    );
    final heading = book.headings.single;
    expect((heading.chapter, heading.verse, heading.part), (2, 4, 'b'));
    expect(
      [for (final v in book.verses) (v.verse, v.part, plainText(v.nodes))],
      [(4, 'a', 'alpha'), (4, 'b', 'beta'), (5, '', 'gamma')],
    );
  });

  test('headings stand over the next verse of the chapter', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 42\n\\ms1 BOOK 2\n\\mr (42-72)\n\\d For the leader.\n'
      '\\q1\n\\v 1 As the deer\n\\s2 Part \\nd Lord\\nd*\n\\r (Ps 1)\n'
      '\\sp Speaker\n\\p\n\\v 2 Thirsts\n\\s Lost\n\\c 43\n\\v 1 Judge',
    );
    expect(
      [for (final h in book.headings) (h.chapter, h.verse, h.kind, h.level)],
      [
        (42, 1, HeadingKind.major, 1),
        (42, 1, HeadingKind.parallel, 1),
        (42, 1, HeadingKind.title, 1),
        (42, 2, HeadingKind.section, 2),
        (42, 2, HeadingKind.parallel, 2),
        (42, 2, HeadingKind.section, 3),
        (43, 1, HeadingKind.section, 1),
      ],
    );
    expect(book.headings[1].nodes, [
      const CrossrefLink(null, [TextRun('(42-72)')]),
    ]);
    expect(book.headings[3].nodes, [
      const TextRun('Part '),
      const StyledSpan(MarkupStyle.divineName, [TextRun('Lord')]),
    ]);
    expect(book.verses[0].nodes, [
      const LineBreak(indent: 1),
      const TextRun('As the deer'),
    ]);
    expect(book.verses[1].nodes, [
      const ParagraphBreak(),
      const TextRun('Thirsts'),
    ]);
    expect(book.droppedFragments, 0);
  });

  test('a heading before a chapter number stands over its first verse', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 a\\f + \\ft x\\f*\n'
      '\\s1 Next\\f + \\ft hn\\f*\n\\c 2\n\\s2 Own\n\\p\n'
      r'\v 1 b\f + \ft y\f*',
    );
    expect(
      [
        for (final h in book.headings)
          (h.chapter, h.verse, h.level, plainText(h.nodes)),
      ],
      [(2, 1, 1, 'Next'), (2, 1, 2, 'Own')],
    );
    expect(book.headings.first.nodes, [
      const TextRun('Next'),
      const FootnoteRef(2, 'a'),
    ]);
    expect(
      book.notes.map(
        (n) => (n.id, n.chapter, n.verse, n.caller, plainText(n.nodes)),
      ),
      [(1, 1, 1, 'a', 'x'), (2, 2, 1, 'a', 'hn'), (3, 2, 1, 'b', 'y')],
    );
    expect(book.verses[1].nodes, [
      const TextRun('b'),
      const FootnoteRef(3, 'b'),
    ]);
    expect(book.droppedFragments, 0);
  });

  test('text after a heading before a chapter number is dropped', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 a\n\\s1 Head\n\\p tail\\f + \\ft t\\f*\n'
      '\\c 2\n\\v 1 b\\f + \\ft n\\f*',
    );
    expect(book.verses.map((v) => plainText(v.nodes)), ['a', 'b']);
    expect([for (final h in book.headings) (h.chapter, h.verse)], [(2, 1)]);
    expect(
      book.notes.map((n) => (n.id, n.chapter, n.caller, plainText(n.nodes))),
      [(1, 2, 'a', 'n')],
    );
    expect(book.droppedFragments, 1);
  });

  test('a speaker label before a chapter number with no text after it', () {
    final book = parseUsfm(
      '\\id SNG\n\\c 1\n\\v 17 a\n\\sp Bride\n\\c 2\n\\v 1 b',
    );
    expect(
      [for (final h in book.headings) (h.chapter, h.verse, plainText(h.nodes))],
      [(2, 1, 'Bride')],
    );
    expect(book.verses.map((v) => plainText(v.nodes)), ['a', 'b']);
    expect(book.droppedFragments, 0);
  });

  test('heading levels are clamped to 1..3', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\s4 Four\n\\s0 Zero\n\\ms9 Nine\n\\ms2 Two\n'
      r'\v 1 One',
    );
    expect(
      [for (final h in book.headings) (h.kind, h.level)],
      [
        (HeadingKind.section, 3),
        (HeadingKind.section, 1),
        (HeadingKind.major, 3),
        (HeadingKind.major, 2),
      ],
    );
  });

  test('a verse number that overflows drops only its marker', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\v 1 One \\wj Lord\n'
      '\\v 99999999999999999999 still one\\wj*\n'
      '\\v 2-99999999999999999999 Two\n\\v 3 Three',
    );
    expect(
      [for (final v in book.verses) (v.verse, v.verseEnd)],
      [(1, null), (2, null), (3, null)],
    );
    // Стиль закрывается на маркере и открывается снова, как на стыке стихов.
    expect(book.verses.first.nodes, [
      const TextRun('One '),
      const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('Lord ')]),
      const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('still one')]),
    ]);
    expect(plainText(book.verses[1].nodes), 'Two');
  });

  test('text after a paragraph stays in its verse', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\p\n\\v 1 One\n\\p two \\qr Amen\n\\b\n'
      '\\v 2 Three\n\\pi2 four\n\\li3 five\n\\qc six\n\\m seven\n'
      r'\nb eight',
    );
    expect(book.verses[0].nodes, [
      const TextRun('One'),
      const ParagraphBreak(),
      const TextRun('two'),
      const LineBreak(align: ParagraphAlign.end),
      const TextRun('Amen'),
    ]);
    expect(book.verses[1].nodes, [
      const ParagraphBreak(gap: true),
      const TextRun('Three'),
      const ParagraphBreak(indent: 2),
      const TextRun('four'),
      const LineBreak(indent: 3),
      const TextRun('five'),
      const LineBreak(align: ParagraphAlign.center),
      const TextRun('six'),
      const ParagraphBreak(continues: true),
      const TextRun('seven eight'),
    ]);
  });

  test('centred, right and indented paragraphs and a letter', () {
    final book = parseUsfm(
      '\\id ACT\n\\c 15\n\\p\n\\v 23 One\n\\pmo Brothers,\n'
      '\\pm greetings\n\\pmc Farewell.\n\\pmr Amen\n\\cls Paul\n'
      '\\v 24 \\pc KING\n\\pr right\n\\mi indented\n\\pi plain\n'
      '\\pi3 deep\n\\po letter',
    );
    expect(book.unknownMarkers, isEmpty);
    expect(book.verses[0].nodes, [
      const TextRun('One'),
      const ParagraphBreak(continues: true, indent: 1),
      const TextRun('Brothers,'),
      const ParagraphBreak(indent: 1),
      const TextRun('greetings'),
      const ParagraphBreak(continues: true, indent: 1),
      const TextRun('Farewell.'),
      const ParagraphBreak(continues: true, align: ParagraphAlign.end),
      const TextRun('Amen'),
      const ParagraphBreak(continues: true, align: ParagraphAlign.end),
      const TextRun('Paul'),
    ]);
    expect(book.verses[1].nodes, [
      const ParagraphBreak(continues: true, align: ParagraphAlign.center),
      const TextRun('KING'),
      const ParagraphBreak(continues: true, align: ParagraphAlign.end),
      const TextRun('right'),
      const ParagraphBreak(continues: true, indent: 1),
      const TextRun('indented'),
      const ParagraphBreak(indent: 1),
      const TextRun('plain'),
      const ParagraphBreak(indent: 3),
      const TextRun('deep'),
      const ParagraphBreak(),
      const TextRun('letter'),
    ]);
  });

  test('a blank line keeps the indent and the alignment of the paragraph '
      'after it', () {
    final book = parseUsfm('\\id MAT\n\\c 27\n\\p\n\\v 37 One\n\\b\n\\pc KING');
    expect(book.verses[0].nodes, [
      const TextRun('One'),
      const ParagraphBreak(
        continues: true,
        gap: true,
        align: ParagraphAlign.center,
      ),
      const TextRun('KING'),
    ]);
  });

  test('a blank line marks the paragraph after it', () {
    final book = parseUsfm(
      '\\id LUK\n\\c 20\n\\p\n\\v 1 One\n\\b\n\\p\n\\v 2 Two\n'
      '\\q1 three\n\\b\n\\q1 four\n\\b\n\\m five\n\\p six',
    );
    expect(book.verses[1].nodes, [
      const ParagraphBreak(gap: true),
      const TextRun('Two'),
      const LineBreak(indent: 1),
      const TextRun('three'),
      const ParagraphBreak(gap: true),
      const LineBreak(indent: 1),
      const TextRun('four'),
      const ParagraphBreak(continues: true, gap: true),
      const TextRun('five'),
      const ParagraphBreak(),
      const TextRun('six'),
    ]);
  });

  test('a blank line at the chapter start gives nothing', () {
    final book = parseUsfm('\\id LUK\n\\c 1\n\\b\n\\p\n\\v 1 One');
    expect(book.verses[0].nodes, [const TextRun('One')]);
  });

  test('a table row that starts a verse belongs to that verse', () {
    // nya, Езд 2, как в архиве: пробелы в конце строк, в пустых ячейках —
    // неразрывные.
    final book = parseUsfm(
      '\\id EZR\n\\c 2\n\\p\n\\v 2 Iwo anabwerera. \n\\b \n'
      '\\mi Chiwerengero:  \n\\tr  \n\\tc1  \n'
      '\\v 3 Zidzukulu za Parosi  \n\\tcr2 2,172  \n'
      '\\tr  \n\\tc1 \u00A0\u00A0  \n'
      '\\v 4 zidzukulu za Sefatiya  \n\\tcr2 372  \n'
      '\\tr  \n\\tc1 \u00A0\u00A0  \n'
      '\\v 5 zidzukulu za Ara  \n\\tcr2 775  \n'
      '\\b \n\\p \n\\v 6 Text',
    );
    final verses = {for (final v in book.verses) v.verse: writeMarkup(v.nodes)};
    expect(verses[2], 'Iwo anabwerera.<p m="1" b="1" i="1"/>Chiwerengero:');
    expect(verses[3], '<tr/><td/>Zidzukulu za Parosi<td a="e"/>2,172');
    expect(verses[4], '<tr/><td/>zidzukulu za Sefatiya<td a="e"/>372');
    expect(verses[5], '<tr/><td/>zidzukulu za Ara<td a="e"/>775');
    // `\b \p` кончает таблицу: стих 6 — как без неё.
    expect(verses[6], '<p b="1"/>Text');
    expect(book.unknownMarkers, isEmpty);
  });

  test('a table inside one verse with headings', () {
    // spaonbv, Числ 1: пустая ячейка из неразрывного пробела.
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 5 Tribu y jefe:\n'
      '\\tr \\th1 Tribu \\th2 Jefe\n'
      '\\tr \\tc1 Rubén \\tc2 Elisur;\n'
      '\\tr \\tc1 hijos de José: \\tc2 \u00A0 \n'
      '\\tr \\tc1 Efraín \\tc2 Elisama;\n'
      '\\b\n\\p\n\\v 16 Text',
    );
    expect(
      writeMarkup(book.verses.first.nodes),
      [
        'Tribu y jefe:<tr/><td h="1"/>Tribu<td h="1"/>Jefe',
        '<tr/><td/>Rubén<td/>Elisur;',
        '<tr/><td/>hijos de José:<td/>',
        '<tr/><td/>Efraín<td/>Elisama;',
      ].join(),
    );
    expect(writeMarkup(book.verses[1].nodes), '<p b="1"/>Text');
    expect(book.unknownMarkers, isEmpty);
  });

  test('right, centred and spanning cells', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 1 \\tr \\thr1 A \\thc2 B\n'
      r'\tr \tcr1 1 \tcc2 2 \tc3-4 3',
    );
    expect(
      writeMarkup(book.verses.single.nodes),
      [
        '<tr/><td h="1" a="e"/>A<td h="1" a="c"/>B',
        '<tr/><td a="e"/>1<td a="c"/>2<td/>3',
      ].join(),
    );
    expect(book.unknownMarkers, isEmpty);
  });

  test('a row that skips the first column gets empty cells', () {
    final book = parseUsfm('\\id NUM\n\\c 1\n\\p\n\\v 1 \\tr \\tc2 x \\tc3 y');
    expect(writeMarkup(book.verses.single.nodes), '<tr/><td/><td/>x<td/>y');
  });

  test('a table ends at a heading and at the chapter', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 6 One\n\\tr \\tc1 a \\tc2 b\n'
      '\\s1 Head\n\\v 7 Seven\n\\tr \\tc1 c\n\\tr \\tc1 \u00A0\n'
      '\\c 2\n\\p\n\\v 1 First',
    );
    final verses = [for (final v in book.verses) writeMarkup(v.nodes)];
    expect(verses, ['One<tr/><td/>a<td/>b', 'Seven<tr/><td/>c', 'First']);
    // Таблица перед заголовком в стих под ним не переходит, таблица в конце
    // главы — в следующую главу.
    expect(verses[1], startsWith('Seven'));
    expect(verses[2], isNot(contains('<t')));
    expect(book.headings.single.verse, 7);
    expect(plainText(book.headings.single.nodes), 'Head');
  });

  test('a trailing empty cell goes to the next verse without a heading', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 6 One \\tr \\tc1 a \\tc2 \u00A0 '
      r'\v 7 Seven',
    );
    expect(
      [for (final v in book.verses) writeMarkup(v.nodes)],
      ['One<tr/><td/>a', '<td/>Seven'],
    );
  });

  test('a heading drops a pending empty cell', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 6 One \\tr \\tc1 a \\tc2 \u00A0 '
      r'\s1 Head \v 7 Seven',
    );
    expect(
      [for (final v in book.verses) writeMarkup(v.nodes)],
      ['One<tr/><td/>a', 'Seven'],
    );
    expect(book.headings.single.verse, 7);
    expect(plainText(book.headings.single.nodes), 'Head');
  });

  test('a poetry line drops a pending empty cell', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 6 One \\tr \\tc1 a \\tc2 \u00A0 '
      r'\q1 \v 7 Seven',
    );
    final verse = writeMarkup(book.verses[1].nodes);
    expect(verse, isNot(contains('<t')));
    expect(verse, '<l i="1"/>Seven');
  });

  test('a table marker inside a note stays plain note text', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 1 One\\f + \\ft a \\tr \\tc1 b\\f* two',
    );
    expect(writeMarkup(book.verses.single.nodes), 'One<f id="1" c="a"/> two');
    expect(plainText(book.notes.single.nodes), 'a b');
    expect(book.unknownMarkers, isEmpty);
  });

  test('a cell past column 32 gets 31 empty cells before it', () {
    final book = parseUsfm('\\id NUM\n\\c 1\n\\p\n\\v 1 \\tr \\tc40 x');
    expect(writeMarkup(book.verses.single.nodes), '<tr/>${'<td/>' * 31}<td/>x');
  });

  test('a table after a mid-verse heading joins the verse as a table', () {
    final book = parseUsfm(
      '\\id NUM\n\\c 1\n\\p\n\\v 1 One\n\\s1 Head\n'
      '\\tr \\tc1 a \\tc2 b\n\\v 2 Two',
    );
    expect(writeMarkup(book.verses.first.nodes), 'One<tr/><td/>a<td/>b');
    expect(book.headings.single.verse, 2);
  });

  test('table markers outside chapters are paragraph breaks', () {
    UsfmBook parse(String intro) =>
        parseUsfm('\\id GEN\n\\ip Intro\n$intro\n\\c 1\n\\v 1 One');
    final table = parse(r'\tr \tc1 a');
    final paragraph = parse(r'\p a');
    expect(
      [for (final i in table.intros) writeMarkup(i.nodes)],
      [for (final i in paragraph.intros) writeMarkup(i.nodes)],
    );
    expect(table.droppedFragments, paragraph.droppedFragments);
    expect(table.unknownMarkers, isEmpty);
  });

  test('notes number in the book and callers in the chapter', () {
    final calls = [for (var i = 0; i < 28; i++) '\\f + \\ft n$i\\f*'];
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\v 1 a${calls.join()}\n'
      // ignore: missing_whitespace_between_adjacent_strings
      '\\c 2\n\\v 1 b\\fe * \\fr 2.1 \\fq word: \\ft end\\fe*'
      r'\x + \xo 2.1 \xt Mt 1:1\x*',
    );
    expect(book.notes, hasLength(30));
    expect(book.notes.map((n) => n.id), [for (var i = 1; i <= 30; i++) i]);
    expect(book.notes[0].caller, 'a');
    expect(book.notes[25].caller, 'z');
    expect(book.notes[26].caller, 'aa');
    expect(book.notes[27].caller, 'ab');
    final fe = book.notes[28];
    expect(
      (fe.chapter, fe.verse, fe.kind, fe.caller),
      (2, 1, FootnoteKind.note, '*'),
    );
    expect(fe.nodes, [
      const StyledSpan(MarkupStyle.emphasis, [TextRun('word: ')]),
      const TextRun('end'),
    ]);
    final x = book.notes[29];
    expect(
      (x.kind, x.caller, plainText(x.nodes)),
      (FootnoteKind.crossref, 'a', 'Mt 1:1'),
    );
    expect(book.verses[1].nodes, [
      const TextRun('b'),
      const FootnoteRef(29, '*'),
      const FootnoteRef(30, 'a'),
    ]);
  });

  test('tagged words, styles and dropped character markers', () {
    final v = parseUsfm(
      // ignore: missing_whitespace_between_adjacent_strings
      '\\id GEN\n\\c 1\n\\v 1 \\va 2\\va*\\vp 1b\\vp*'
      r'\w In|strong="H0430,H08804" x-morph="He,R"\w* '
      r'\w the|lemma="x"\w* \w be|strong="H1 G02"\w* '
      r'\em e\em* \it i\it* \qt q\qt* \bd b\bd* \sc s\sc* \bdit bi\bdit* '
      r'\fig pic|src="a.jpg"\fig*x~y // z',
    ).verses.single;
    expect(v.nodes, [
      const TaggedWord(
        [TextRun('In')],
        strong: ['H430', 'H8804'],
        morph: 'He,R',
      ),
      const TextRun(' the '),
      const TaggedWord([TextRun('be')], strong: ['H1', 'G2']),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.emphasis, [TextRun('e')]),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.emphasis, [TextRun('i')]),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.quote, [TextRun('q')]),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.bold, [TextRun('b')]),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.smallCaps, [TextRun('s')]),
      const TextRun(' '),
      const StyledSpan(MarkupStyle.bold, [
        StyledSpan(MarkupStyle.emphasis, [TextRun('bi')]),
      ]),
      const TextRun(' x\u00A0y z'),
    ]);
  });

  test('bold italic carries over a verse and closes whole', () {
    final book = parseUsfm('\\id MAT\n\\c 1\n\\v 1 \\bdit a\n\\v 2 b\\bdit* c');
    expect(book.verses[1].nodes, [
      const StyledSpan(MarkupStyle.bold, [
        StyledSpan(MarkupStyle.emphasis, [TextRun('b')]),
      ]),
      const TextRun(' c'),
    ]);
  });

  test('styles carry over a verse and close at a paragraph', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 5\n\\v 1 \\wj a\n\\v 2 b\n\\p c\\wj* d\n\\yy e\n'
      r'\v 3 f',
    );
    expect(book.verses[0].nodes, [
      const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('a')]),
    ]);
    expect(book.verses[1].nodes, [
      const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('b')]),
      const ParagraphBreak(),
      const TextRun('c d'),
      const ParagraphBreak(),
      const TextRun('e'),
    ]);
    expect(book.unknownMarkers, {'yy'});
  });

  test('mid-verse heading keeps the text after it in the verse', () {
    final book = parseUsfm(
      '\\id SNG\n\\c 1\n\\v 4 Take me away.\n\\sp Friends\n'
      '\\q1 We will be glad\\f + \\ft n\\f*\n\\v 5 I am dark',
    );
    expect(book.verses.first.nodes, [
      const TextRun('Take me away.'),
      const LineBreak(indent: 1),
      const TextRun('We will be glad'),
      const FootnoteRef(1, 'a'),
    ]);
    final heading = book.headings.single;
    expect(
      (heading.chapter, heading.verse, heading.kind, heading.level),
      (1, 5, HeadingKind.section, 3),
    );
    expect(plainText(heading.nodes), 'Friends');
    expect(book.notes.single.verse, 4);
    expect(book.droppedFragments, 0);
  });

  test('text before the first verse continues the heading', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 10\n\\d Начальнику хора.\n\\m Псалом Давида.\n\\q1\n'
      '\\v 1 На Господа уповаю\n\\c 11\n\\d A\\m B\n\\v 1 C',
    );
    expect(book.headings.map((h) => (h.kind, plainText(h.nodes))), [
      (HeadingKind.title, 'Начальнику хора. Псалом Давида.'),
      (HeadingKind.title, 'A B'),
    ]);
    expect(book.verses.first.nodes, [
      const LineBreak(indent: 1),
      const TextRun('На Господа уповаю'),
    ]);
    expect(book.droppedFragments, 0);
  });

  test('heading at the chapter end drops itself and the text after it', () {
    final book = parseUsfm(
      '\\id ROM\n\\s Prologue\n\\p Text before\n\\c 16\n'
      '\\v 26 x\\f + \\ft keep\\f*\n\\v 27 Amen.\n'
      '\\s1 Written \\f + \\ft gone\\f*\n\\p to the Romans\\f + \\ft gone\\f*',
    );
    expect(book.verses.last.nodes, [const TextRun('Amen.')]);
    expect(book.headings, isEmpty);
    expect(book.notes.map((n) => plainText(n.nodes)), ['keep']);
    expect(book.droppedFragments, 2);
  });

  test('extended notes are notes and cross references', () {
    final book = parseUsfm(
      // ignore: missing_whitespace_between_adjacent_strings
      '\\id MAT\n\\c 1\n\\v 1 a\\ef + \\fr 1.1 \\ft study\\ef*'
      r'\ex - \xo 1.1 \xt Mt 1:1\ex*',
    );
    expect(book.notes.map((n) => (n.kind, n.caller, plainText(n.nodes))), [
      (FootnoteKind.note, 'a', 'study'),
      (FootnoteKind.crossref, '', 'Mt 1:1'),
    ]);
    expect(book.verses.single.nodes, [
      const TextRun('a'),
      const FootnoteRef(1, 'a'),
      const FootnoteRef(2, ''),
    ]);
  });

  test('trailing speaker label drops only itself', () {
    final book = parseUsfm(
      '\\id SNG\n\\c 6\n\\v 13 Return!\n\\sp Lover\\f + \\ft label\\f*\n'
      '\\q1 Why do you gaze\\f + \\ft n\\f*\n'
      '\\c 7\n\\v 1 How\n\\sp Friends\n\\p kept\n\\s1 Subscription\n\\p gone',
    );
    expect(book.verses[0].nodes, [
      const TextRun('Return!'),
      const LineBreak(indent: 1),
      const TextRun('Why do you gaze'),
      const FootnoteRef(1, 'a'),
    ]);
    expect(book.verses[1].nodes, [
      const TextRun('How'),
      const ParagraphBreak(),
      const TextRun('kept'),
    ]);
    expect(book.headings, isEmpty);
    expect(
      book.notes.map((n) => (n.id, n.chapter, n.verse, plainText(n.nodes))),
      [(1, 6, 13, 'n')],
    );
    expect(book.droppedFragments, 4);
  });

  test('a part of the other kind or an unknown marker stays in the note', () {
    final book = parseUsfm(
      // ignore: missing_whitespace_between_adjacent_strings
      '\\id GEN\n\\c 1\n\\v 1 a\\f + \\fr 1:1 \\ft see \\xt Gen 1:2\\f* b'
      r'\x + \xo 1:1 \ft also \zq odd\x* c',
    );
    expect(book.notes.map((n) => plainText(n.nodes)), [
      'see Gen 1:2',
      'also odd',
    ]);
    expect(book.verses.single.nodes, [
      const TextRun('a'),
      const FootnoteRef(1, 'a'),
      const TextRun(' b'),
      const FootnoteRef(2, 'b'),
      const TextRun(' c'),
    ]);
    expect(book.unknownMarkers, {'zq'});
  });

  test('a note between spaces sticks to the word before it', () {
    // BSB, Плач 4:7: пробел и перед `\f`, и после `\f*`.
    final book = parseUsfm(
      '\\id LAM\n\\c 4\n'
      r'\v 7 their appearance \f + \fr 4:7 \ft Or polishing\f* '
      r'\w like|strong="H7950"\w* sapphire'
      '\n\\v 8 a \\wj b \\f + \\ft n\\f* c\\wj*',
    );
    expect(book.verses[0].nodes, [
      const TextRun('their appearance'),
      const FootnoteRef(1, 'a'),
      const TextRun(' '),
      const TaggedWord([TextRun('like')], strong: ['H7950']),
      const TextRun(' sapphire'),
    ]);
    expect(book.verses[1].nodes, [
      const TextRun('a '),
      const StyledSpan(MarkupStyle.wordsOfChrist, [
        TextRun('b'),
        FootnoteRef(2, 'b'),
        TextRun(' c'),
      ]),
    ]);
  });

  test('a note between spaces at a span start keeps the space after it', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 a \\wj \\f + \\ft n\\f* b\\wj*',
    );
    expect(book.verses.single.nodes, [
      const TextRun('a '),
      const StyledSpan(MarkupStyle.wordsOfChrist, [
        FootnoteRef(1, 'a'),
        TextRun(' b'),
      ]),
    ]);
  });

  test('text after a mid-verse heading joins the verse', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 word\\s Head\n\\nb\\f + \\ft n\\f* more\n'
      '\\v 2 a\\s Head\n\\nb b\n\\v 3 c',
    );
    expect(book.verses[0].nodes, [
      const TextRun('word'),
      const FootnoteRef(1, 'a'),
      const TextRun(' more'),
    ]);
    expect(book.verses[1].nodes, [const TextRun('a b')]);
  });

  test('text outside headings and verses is dropped and counted', () {
    final title = parseUsfm(
      '\\id SIR\n\\c 51\n\\p A Prayer of Jesus.\n\\p\n\\v 1 I will thank',
    );
    expect(title.headings, isEmpty);
    expect(title.verses.single.nodes, [const TextRun('I will thank')]);
    expect(title.droppedFragments, 1);
    final label = parseUsfm(
      '\\id SNG\n\\c 1\n\\sp Lover\n\\p text\n\\c 2\n\\v 1 x\n\\c 3\n\\p y',
    );
    expect(
      [
        for (final h in label.headings)
          (h.chapter, h.verse, plainText(h.nodes)),
      ],
      [(2, 1, 'Lover text')],
    );
    expect(label.verses.single.nodes, [const TextRun('x')]);
    expect(label.droppedFragments, 1);
  });

  test('a milestone without its end eats only its own line', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 a \\qt-s |who="x"\n\\v 2 b \\ts\\*\n\\v 3 c',
    );
    expect([for (final v in book.verses) plainText(v.nodes)], ['a', 'b', 'c']);
  });

  test('introduction before the first chapter is kept', () {
    final book = parseUsfm(
      '\\id SIR\n\\imt ПРЕДИСЛОВИЕ\\f ** \\ft С.\\f*\n\\ip Многое…\n'
      '\\c 1\n\\v 1 Т',
    );
    expect(book.intros.map((intro) => intro.kind), [
      IntroKind.title,
      IntroKind.paragraph,
    ]);
    expect(book.intros[0].nodes, [
      const TextRun('ПРЕДИСЛОВИЕ'),
      const FootnoteRef(1, '**'),
    ]);
    expect(book.intros[1].nodes, [const TextRun('Многое…')]);
    final note = book.notes.single;
    expect((note.id, note.chapter, note.verse, note.caller), (1, 0, 0, '**'));
    expect(plainText(note.nodes), 'С.');
    expect(plainText(book.verses.single.nodes), 'Т');
    expect(book.droppedFragments, 0);
  });

  test('introduction markers choose the kind or drop out', () {
    final book = parseUsfm(
      '\\id GEN\n\\is1 Section\n\\ipi Indented\n\\im Flush\n\\ipq Quote\n'
      '\\iq1 Line\n\\io1 Outline\n\\iot Outline title\n\\ie\n\\ide UTF-8\n'
      '\\c 1\n\\v 1 x',
    );
    expect(book.intros.map((i) => (i.kind, plainText(i.nodes))), [
      (IntroKind.title, 'Section'),
      (IntroKind.paragraph, 'Indented'),
      (IntroKind.paragraph, 'Flush'),
      (IntroKind.paragraph, 'Quote'),
      (IntroKind.paragraph, 'Line'),
    ]);
  });

  test('an introduction marker after a chapter stays unknown', () {
    final book = parseUsfm('\\id GEN\n\\c 1\n\\ip Late\n\\v 1 x');
    expect(book.intros, isEmpty);
    expect(book.unknownMarkers, {'ip'});
  });

  test('major titles before the first chapter are lines of the book title', () {
    final book = parseUsfm(
      '\\id GEN\n\\h Genesis\n\\toc1 The Book\n\\mt2 The First Book\n'
      '\\mt1 Genesis\\f + \\ft n\\f*\n\\mt3 Small\n\\mt Plain\n\\mte End\n'
      '\\ms Major\n\\imt Intro\n\\c 1\n\\v 1 x',
    );
    expect(book.intros.map((i) => (i.kind, plainText(i.nodes))), [
      (IntroKind.bookSubtitle, 'The First Book'),
      (IntroKind.bookTitle, 'Genesis'),
      (IntroKind.bookSubtitle, 'Small'),
      (IntroKind.bookTitle, 'Plain'),
      (IntroKind.title, 'Intro'),
    ]);
    // Сноска заглавия — сноска вступления, как у `\imt`.
    expect(book.intros[1].nodes, [
      const TextRun('Genesis'),
      const FootnoteRef(1, 'a'),
    ]);
    final note = book.notes.single;
    expect((note.id, note.chapter, note.verse), (1, 0, 0));
    expect(book.header, 'Genesis');
    expect(book.toc1, 'The Book');
    expect(book.droppedFragments, 0);
    expect(book.unknownMarkers, isEmpty);
  });

  test('a major title after a chapter stays unknown', () {
    final book = parseUsfm('\\id GEN\n\\c 1\n\\mt1 Late\n\\v 1 x');
    expect(book.intros, isEmpty);
    expect(book.unknownMarkers, {'mt1'});
  });

  test('a verse label stands for the number and leaves the text', () {
    final book = parseUsfm(
      '\\id 2CH\n\\c 36\n\\p\n\\v 23 А\n'
      '\\v 24 \\zvl а\\zvl* Господи, \\zvl праведного\\zvl*,\n'
      '\\v 25 \\zvl\\zvl* Аминь.\n'
      '\\v 26 \\zvl б \\it в\\it*\\zvl* Г\n'
      '\\v 27 Д\\f + \\zvl x\\zvl* \\ft note\\f*\n',
    );
    final verses = {for (final v in book.verses) v.verse: v};
    expect(verses[23]!.label, isNull);
    // Вторая помета в стихе заменяет первую, её текст в стих не идёт.
    expect(verses[24]!.label, 'праведного');
    expect(plainText(verses[24]!.nodes), 'Господи, ,');
    expect(verses[25]!.label, '');
    expect(plainText(verses[25]!.nodes), 'Аминь.');
    // Маркер внутри метки её заканчивает.
    expect(verses[26]!.label, 'б');
    // В сноске помета не метка стиха.
    expect(verses[27]!.label, isNull);
    expect(book.unknownMarkers, isEmpty);
  });

  test('a published verse number is kept and leaves the text', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\p\n\\v 1-5 \\vp 1–6а\\vp* А\n'
      '\\p\n\\v 6-11 \\vp 6б–11 \\vp* Б\n'
      '\\v 12 \\vp\\vp* В\n'
      '\\v 13 Г\\f + \\vp x\\vp* \\ft note\\f*\n',
    );
    final verses = {for (final v in book.verses) v.verse: v};
    expect(verses[1]!.number, '1–6а');
    expect(verses[1]!.verseEnd, 5);
    expect(plainText(verses[1]!.nodes), 'А');
    expect(verses[6]!.number, '6б–11');
    expect(plainText(verses[6]!.nodes), 'Б');
    // Пустая помета номера не даёт.
    expect(verses[12]!.number, isNull);
    // В сноске помета не номер стиха.
    expect(verses[13]!.number, isNull);
    expect(verses[1]!.label, isNull);
    expect(book.unknownMarkers, isEmpty);
  });

  test('an acrostic letter is a heading above the next verse', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 119\n\\qa Alefu\n\\q1\n\\v 1 Odala\n'
      '\\q1\n\\v 8 Ndidzamvera\n\\qa Beti\n\\q1\n\\v 9 Kodi\n',
    );
    expect(
      [
        for (final h in book.headings)
          (h.verse, h.kind, h.level, plainText(h.nodes)),
      ],
      [
        (1, HeadingKind.acrostic, 1, 'Alefu'),
        (9, HeadingKind.acrostic, 1, 'Beti'),
      ],
    );
    expect(
      plainText(book.verses.firstWhere((v) => v.verse == 8).nodes),
      isNot(contains('Beti')),
    );
    expect(book.unknownMarkers, isNot(contains('qa')));
  });

  test('an acrostic letter keeps its footnote', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 119\n'
      '\\qa Aleph\\f + \\fr 119.0 \\ft Acróstico.\\f*\n\\q1\n\\v 1 Felices',
    );
    expect(book.headings.single.nodes.whereType<FootnoteRef>(), hasLength(1));
    expect(plainText(book.notes.single.nodes), 'Acróstico.');
  });

  test('a section heading and an acrostic letter over one verse', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 119\n\\s1 Law\n\\qa ਅਲਫ਼\n\\q1\n\\v 1 Text',
    );
    expect(
      [for (final h in book.headings) (h.verse, h.kind)],
      [(1, HeadingKind.section), (1, HeadingKind.acrostic)],
    );
  });

  test('an acrostic line letter is bold', () {
    final book = parseUsfm(
      '\\id PSA\n\\c 37\n\\q1\n\\v 1 \\qac A\\qac*brtzlvz',
    );
    expect(book.verses.single.nodes, [
      const LineBreak(indent: 1),
      const StyledSpan(MarkupStyle.bold, [TextRun('A')]),
      const TextRun('brtzlvz'),
    ]);
    expect(book.unknownMarkers, isNot(contains('qac')));
  });

  test('a quote source stays in the verse', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\p\n\\v 18 Text. \\rq Luk 1:27\\rq*\n\\p\n\\v 19 Next',
    );
    expect(book.verses[0].nodes, [
      const TextRun('Text. '),
      const StyledSpan(MarkupStyle.quoteSource, [
        CrossrefLink(null, [TextRun('Luk 1:27')]),
      ]),
    ]);
    expect(book.verses[1].nodes, [
      const ParagraphBreak(),
      const TextRun('Next'),
    ]);
    expect(book.unknownMarkers, isNot(contains('rq')));
  });
}
