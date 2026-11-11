import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

UsfmSource _file(String name, String text) =>
    (name: name, bytes: utf8.encode(text));

String _book(String code, {String verse = 'In the beginning.'}) =>
    '\\id $code\n\\h $code\n\\c 1\n\\p\n\\v 1 $verse\n';

ModuleMeta _meta(String language) => ModuleMeta(
  type: ModuleType.bible,
  abbreviation: 'TST',
  name: 'Test',
  language: language,
  direction: WritingDirection.ltr,
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('usfm_module_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('reads books in name order and skips what is not a bible book', () {
    final books = readUsfmBooks([
      _file('b.usfm', _book('EXO')),
      _file('a.usfm', _book('GEN')),
      _file('c.usfm', _book('GLO')),
      _file('d.usfm', '\\c 1\n\\p\n\\v 1 No id.\n'),
    ]);

    expect(books.books.map((book) => book.number), [10, 20]);
    expect(
      books.warnings,
      containsAll(['GLO: not in the book catalog, skipped']),
    );
    expect(books.warnings, contains(r'd.usfm: no \id, skipped'));
  });

  test('decodes utf-8 with a bom and utf-16 both ways', () {
    const text = '\\id GEN\n\\c 1\n\\p\n\\v 1 Начало.\n';
    final utf16 = text.codeUnits;
    final le = Uint8List(utf16.length * 2);
    final be = Uint8List(utf16.length * 2);
    for (var i = 0; i < utf16.length; i++) {
      le[i * 2] = utf16[i] & 0xFF;
      le[i * 2 + 1] = utf16[i] >> 8;
      be[i * 2] = utf16[i] >> 8;
      be[i * 2 + 1] = utf16[i] & 0xFF;
    }
    final variants = <List<int>>[
      [0xEF, 0xBB, 0xBF, ...utf8.encode(text)],
      [0xFF, 0xFE, ...le],
      [0xFE, 0xFF, ...be],
    ];

    for (final bytes in variants) {
      final book = parseUsfm(decodeUsfm(bytes));
      expect(book.code, 'GEN');
      expect(plainText(book.verses.first.nodes), 'Начало.');
    }
  });

  test('progress goes up to one', () {
    final reads = <double>[];
    final books = readUsfmBooks([
      _file('a.usfm', _book('GEN')),
      _file('b.usfm', _book('EXO')),
      _file('c.usfm', _book('LEV')),
    ], onProgress: reads.add);
    expect(reads, hasLength(3));
    expect(reads.last, 1);
    for (var i = 1; i < reads.length; i++) {
      expect(reads[i], greaterThan(reads[i - 1]));
    }

    final writes = <double>[];
    writeUsfmModule(
      '${dir.path}/p.hb',
      _meta('und'),
      books,
      onProgress: writes.add,
    );
    expect(writes, hasLength(3));
    expect(writes.last, 1.0);
    for (var i = 1; i < writes.length; i++) {
      expect(writes[i], greaterThan(writes[i - 1]));
    }
  });

  test('writes a module that opens', () {
    final books = readUsfmBooks([
      _file('b.usfm', _book('EXO', verse: 'Names.')),
      _file('a.usfm', _book('GEN')),
    ]);
    final path = '${dir.path}/m.hb';

    writeUsfmModule(path, _meta('und'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.books.map((book) => book.number), [10, 20]);
      expect(module.chapter(10, 1).single.text, 'In the beginning.');
    } finally {
      module.close();
    }
  });

  test('ru order follows the russian catalog order', () {
    final books = readUsfmBooks([
      _file('a.usfm', _book('ROM')),
      _file('b.usfm', _book('JAS')),
    ]);
    final path = '${dir.path}/ru.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      final jas = BookCatalog.numberOfCode('JAS');
      final rom = BookCatalog.numberOfCode('ROM');
      expect(module.books.map((book) => book.number), [jas, rom]);
    } finally {
      module.close();
    }
  });

  test('intros and their footnotes are written', () {
    String book(String code) =>
        '\\id $code\n\\imt Title\\f + \\ft intro $code\\f*\n\\ip Body\n'
        '\\c 1\n\\p\n\\v 1 Verse\\f + \\ft verse $code\\f*\n';
    final books = readUsfmBooks([
      _file('a.usfm', book('GEN')),
      _file('b.usfm', book('EXO')),
    ]);
    final path = '${dir.path}/i.hb';

    writeUsfmModule(path, _meta('und'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.intros(10).map((i) => (i.position, i.kind)), [
        (0, IntroKind.title),
        (1, IntroKind.paragraph),
      ]);
      expect(module.intros(10)[1].text, 'Body');
      final ids = <int>{};
      for (final number in [10, 20]) {
        final intro = module.footnotes(number, 0).single;
        expect((intro.chapter, intro.verse), (0, 0));
        expect(intro.text, 'intro ${number == 10 ? 'GEN' : 'EXO'}');
        final verse = module.footnotes(number, 1).single;
        expect(verse.verse, 1);
        ids
          ..add(intro.id)
          ..add(verse.id);
        expect(
          module.intros(number).first.text,
          contains('<f id="${intro.id}"'),
        );
      }
      expect(ids, hasLength(4));
    } finally {
      module.close();
    }
  });

  test("a footnote in a heading takes the heading's place", () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id 2CH\n\\c 36\n\\p\n\\v 23 А\n'
            '\\s1 Молитва\\f * \\ft П.\\f*\n\\v 24 Б\n',
      ),
    ]);
    final path = '${dir.path}/h.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      final note = module.footnotes(140, 36).single;
      expect((note.chapter, note.verse, note.caller), (36, 24, '*'));
      expect(note.text, 'П.');
      final heading = module.headings(140, 36).single;
      expect(heading.verse, 24);
      expect(heading.text, contains('<f id="${note.id}"'));
    } finally {
      module.close();
    }
  });
}
