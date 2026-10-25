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
}
