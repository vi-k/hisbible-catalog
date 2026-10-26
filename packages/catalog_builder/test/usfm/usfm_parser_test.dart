import 'package:catalog_builder/catalog_builder.dart';
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

  test('verse parts join and chapters number verses anew', () {
    final book = parseUsfm(
      '\\id GEN\n\\c 1\n\\v 1a first\n\\v 1b second\n\\v 2 two\n'
      '\\c 2\n\\v 1 again',
    );
    expect(
      [for (final v in book.verses) (v.chapter, v.verse)],
      [(1, 1), (1, 2), (2, 1)],
    );
    expect(book.verses.first.nodes, [const TextRun('first second')]);
    expect(book.verses.first.verseEnd, isNull);
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
        (42, 1, HeadingKind.title, 1),
        (42, 2, HeadingKind.section, 2),
        (42, 2, HeadingKind.section, 3),
      ],
    );
    expect(book.headings[2].nodes, [
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
    expect(book.droppedFragments, 1);
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
      const LineBreak(),
      const TextRun('Amen'),
    ]);
    expect(book.verses[1].nodes, [
      const ParagraphBreak(),
      const TextRun('Three'),
      const ParagraphBreak(),
      const TextRun('four'),
      const LineBreak(indent: 3),
      const TextRun('five'),
      const LineBreak(),
      const TextRun('six'),
      const ParagraphBreak(),
      const TextRun('seven eight'),
    ]);
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
      r'\em e\em* \it i\it* \qt q\qt* \bd b\bd* \sc s\sc* '
      r'\rq Mt 1\rq*\fig pic|src="a.jpg"\fig*x~y // z',
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
      const TextRun(' b s x\u00A0y z'),
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
      '\\id SNG\n\\c 1\n\\sp Lover\n\\p text\n\\c 2\n\\v 1 x',
    );
    expect(label.headings, isEmpty);
    expect(label.verses.single.nodes, [const TextRun('x')]);
    expect(label.droppedFragments, 1);
  });

  test('a milestone without its end eats only its own line', () {
    final book = parseUsfm(
      '\\id MAT\n\\c 1\n\\v 1 a \\qt-s |who="x"\n\\v 2 b \\ts\\*\n\\v 3 c',
    );
    expect([for (final v in book.verses) plainText(v.nodes)], ['a', 'b', 'c']);
  });
}
