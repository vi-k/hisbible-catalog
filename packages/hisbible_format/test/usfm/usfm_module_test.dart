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

  test('a scheme set by hand beats the detected one', () {
    final books = readUsfmBooks([
      _file('a.usfm', _book('GEN')),
      _file('b.usfm', _book('EXO', verse: 'Names.')),
    ]);
    final path = '${dir.path}/m.hb';

    writeUsfmModule(
      path,
      _meta('und'),
      books,
      schemes: {20: VerseScheme.org, 300: VerseScheme.rso},
    );

    final module = BibleModule.open(path);
    try {
      expect(module.schemes.of(10), VerseScheme.eng);
      expect(module.schemes.of(20), VerseScheme.org);
      // Книги, которой в модуле нет, ручная схема не добавляет.
      expect(module.schemes.schemes.keys, unorderedEquals([10, 20]));
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

  test('the front matter file is the preface of the module', () {
    final books = readUsfmBooks([
      _file(
        '00-FRT.usfm',
        '\\id FRT\n\\imt1 Предисловие\n'
            '\\ip Дорогой\\f + \\ft сноска\\f* читатель!\n',
      ),
      _file('01-GEN.usfm', '\\id GEN\n\\c 1\n\\p\n\\v 1 В начале\n'),
    ]);
    expect(books.books.map((book) => book.number), [10]);
    expect(books.preface.map((part) => part.kind), [
      IntroKind.title,
      IntroKind.paragraph,
    ]);
    expect(books.warnings, isEmpty);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.preface(), const [
        Intro(0, IntroKind.title, 'Предисловие'),
        Intro(1, IntroKind.paragraph, 'Дорогой<f id="1" c="a"/> читатель!'),
      ]);
      expect(module.prefaceFootnotes(), const [
        Footnote(1, 0, 0, 0, FootnoteKind.note, 'a', 'сноска'),
      ]);
      expect(module.intros(10), isEmpty);
      expect(module.footnotes(10, 0), isEmpty);
    } finally {
      module.close();
    }
  });

  test('a periph in the front matter opens an article', () {
    final books = readUsfmBooks([
      _file(
        '00-FRT.usfm',
        '\\id FRT\n\\ip Титул\n'
            '\\periph Слово к читателю\n\\ip Книга\n'
            '\\periph Послесловие|id="afterword"\n\\is Часть I\n\\ip Прошло\n',
      ),
      _file('01-GEN.usfm', '\\id GEN\n\\c 1\n\\p\n\\v 1 В начале\n'),
    ]);
    expect(books.warnings, isEmpty);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.preface(), const [
        Intro(0, IntroKind.paragraph, 'Титул'),
        Intro(1, IntroKind.article, 'Слово к читателю'),
        Intro(2, IntroKind.paragraph, 'Книга'),
        Intro(3, IntroKind.article, 'Послесловие'),
        Intro(4, IntroKind.title, 'Часть I'),
        Intro(5, IntroKind.paragraph, 'Прошло'),
      ]);
    } finally {
      module.close();
    }
  });

  test('notes of books follow the notes of the preface', () {
    final books = readUsfmBooks([
      _file(
        '00-FRT.usfm',
        '\\id FRT\n\\ip А\\f 1 \\ft первая\\f* Б\\f 2 \\ft вторая\\f*\n',
      ),
      _file(
        '01-GEN.usfm',
        '\\id GEN\n\\c 1\n\\p\n\\v 1 В начале\\f + \\ft книги\\f*\n',
      ),
    ]);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.prefaceFootnotes().map((note) => note.id), [1, 2]);
      expect(module.footnotes(10, 1), const [
        Footnote(3, 10, 1, 1, FootnoteKind.note, 'a', 'книги'),
      ]);
      expect(module.chapter(10, 1).single.text, 'В начале<f id="3" c="a"/>');
    } finally {
      module.close();
    }
  });

  test('a link outside a note keeps its place', () {
    final books = readUsfmBooks([
      _file(
        '00-FRT.usfm',
        '\\id FRT\n\\ip См. \\xt Ио 1:1|link-href="JHN 1:1"\\xt* '
            'и \\xt Мк 2|x-other="1"\\xt*.\n',
      ),
      _file('01-GEN.usfm', '\\id GEN\n\\c 1\n\\p\n\\v 1 В начале\n'),
    ]);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.preface(), const [
        Intro(0, IntroKind.paragraph, 'См. <x r="JHN.1.1">Ио 1:1</x> и Мк 2.'),
      ]);
    } finally {
      module.close();
    }
  });

  test('a list item and the author of an article', () {
    final books = readUsfmBooks([
      _file(
        '00-FRT.usfm',
        '\\id FRT\n'
            '\\periph Слово|id="word" x-author="Митрополит Владимир"\n'
            '\\ip Текст\n\\periph Сокращения\n\\ili Быт — Бытие\n'
            '\\ili2 ВЗ — Ветхий Завет\n',
      ),
      _file('01-GEN.usfm', '\\id GEN\n\\c 1\n\\p\n\\v 1 В начале\n'),
    ]);
    expect(books.warnings, isEmpty);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.prefaceArticles(), const [
        PrefaceArticle('Слово', [
          Intro(2, IntroKind.paragraph, 'Текст'),
        ], author: 'Митрополит Владимир'),
        PrefaceArticle('Сокращения', [
          Intro(4, IntroKind.item, 'Быт — Бытие'),
          Intro(5, IntroKind.item, 'ВЗ — Ветхий Завет'),
        ]),
      ]);
    } finally {
      module.close();
    }
  });

  test('a periph in a book is a title of its intro', () {
    final books = readUsfmBooks([
      _file(
        '01-GEN.usfm',
        '\\id GEN\n\\periph Вступление|x-author="Пётр"\n\\ip Книга\n'
            '\\c 1\n\\p\n\\v 1 В начале\n',
      ),
    ]);
    expect(books.warnings, [r'GEN: \periph outside FRT, read as a title: 1']);
    final path = '${dir.path}/p.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.intros(10), const [
        Intro(0, IntroKind.title, 'Вступление'),
        Intro(1, IntroKind.paragraph, 'Книга'),
      ]);
    } finally {
      module.close();
    }
  });

  test('verse labels are written', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id 2CH\n\\c 36\n\\p\n\\v 23 А\n'
            '\\v 24 \\zvl а\\zvl* Б,\n\\v 25 \\zvl\\zvl* В.\n',
      ),
    ]);
    final path = '${dir.path}/l.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.verseLabels(140, 36), const {
        (verse: 24, part: ''): 'а',
        (verse: 25, part: ''): '',
      });
      expect(module.verseLabels(140, 35), isEmpty);
      expect(module.chapter(140, 36)[1].text, 'Б,');
    } finally {
      module.close();
    }
  });

  test('published verse numbers are written', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id MAT\n\\c 1\n\\p\n\\v 1-5 \\vp 1–6а\\vp* А\n'
            '\\v 6-11 \\vp 6б–11\\vp* Б\n\\v 12 В\n',
      ),
    ]);
    final path = '${dir.path}/n.hb';

    writeUsfmModule(path, _meta('ru'), books);

    final module = BibleModule.open(path);
    try {
      expect(module.verseNumbers(470, 1), const {
        (verse: 1, part: ''): '1–6а',
        (verse: 6, part: ''): '6б–11',
      });
      expect(module.chapter(470, 1).map((v) => (v.verse, v.verseEnd)), [
        (1, 5),
        (6, 11),
        (12, null),
      ]);
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

  test('Zechariah 4 keeps its pieces', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id ZEC\n\\c 4\n\\p\n\\v 1-5 alpha\n\\v 6a beta\n'
            '\\v 10b-14 gamma\n\\s Heading\n\\p\n'
            '\\v 6b-10a \\vp 6b–10a\\vp* \\zvl b\\zvl* delta\n',
      ),
    ]);
    final path = '${dir.path}/z.hb';

    writeUsfmModule(path, _meta('und'), books);

    expect(books.warnings, isEmpty);
    expect(checkModuleFile(path), isNull);
    final module = BibleModule.open(path);
    try {
      expect(
        [for (final v in module.chapter(450, 4)) (v.label, v.text)],
        [
          ('1–5', 'alpha'),
          ('6a', 'beta'),
          ('10b–14', 'gamma'),
          ('6b–10a', '<p/>delta'),
        ],
      );
      expect(module.headings(450, 4), const [
        Heading(6, 0, HeadingKind.section, 1, 'Heading', part: 'b'),
      ]);
      expect(module.verseNumbers(450, 4), const {
        (verse: 6, part: 'b'): '6b–10a',
      });
      expect(module.verseLabels(450, 4), const {(verse: 6, part: 'b'): 'b'});
    } finally {
      module.close();
    }
  });

  test('a repeated piece is dropped', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id GEN\n\\c 1\n\\p\n\\v 3 alpha\n\\v 4 beta\n\\v 3 gamma\n'
            '\\v 6b delta\n\\s Kept\n\\v 7 zeta\n\\s Lost\n\\v 6b epsilon\n',
      ),
    ]);
    final path = '${dir.path}/r.hb';

    writeUsfmModule(path, _meta('und'), books);

    expect(books.warnings, [
      'GEN 1:3: repeated verse, skipped',
      'GEN 1:6b: repeated verse, skipped',
    ]);
    final module = BibleModule.open(path);
    try {
      expect(
        [for (final v in module.chapter(10, 1)) (v.label, v.text)],
        [('3', 'alpha'), ('4', 'beta'), ('6b', 'delta'), ('7', 'zeta')],
      );
      expect([for (final h in module.headings(10, 1)) h.text], ['Kept']);
    } finally {
      module.close();
    }
  });

  test('an adjacent repeat joins its piece', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id GEN\n\\c 1\n\\p\n\\v 3 alpha\n\\v 3 beta\n'
            '\\v 6b gamma\n\\v 6b-8 delta\n\\v 9 epsilon\n',
      ),
    ]);
    final path = '${dir.path}/j.hb';

    writeUsfmModule(path, _meta('und'), books);

    expect(books.warnings, isEmpty);
    expect(checkModuleFile(path), isNull);
    final module = BibleModule.open(path);
    try {
      expect(
        [for (final v in module.chapter(10, 1)) (v.label, v.text)],
        [('3', 'alpha beta'), ('6b–8', 'gamma delta'), ('9', 'epsilon')],
      );
    } finally {
      module.close();
    }
  });

  test('an end that reaches a later piece is cut', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id GEN\n\\c 1\n\\p\n\\v 1-7 alpha\n\\v 6b beta\n'
            '\\c 2\n\\p\n\\v 6b gamma\n\\v 1-7 delta\n'
            '\\c 3\n\\p\n\\v 1-6b epsilon\n\\v 6b zeta\n',
      ),
    ]);
    final path = '${dir.path}/e.hb';

    writeUsfmModule(path, _meta('und'), books);

    expect(books.warnings, [
      'GEN 1:1-7: reaches verse 6b, written as one verse',
      'GEN 2:1-7: reaches verse 6b, written as one verse',
      'GEN 3:1-6b: reaches verse 6b, written as one verse',
    ]);
    expect(checkModuleFile(path), isNull);
    final module = BibleModule.open(path);
    try {
      expect([for (final v in module.chapter(10, 1)) v.label], ['1', '6b']);
      expect([for (final v in module.chapter(10, 2)) v.label], ['6b', '1']);
      expect([for (final v in module.chapter(10, 3)) v.label], ['1', '6b']);
    } finally {
      module.close();
    }
  });

  test('pieces from USFM pass the module check', () {
    final books = readUsfmBooks([
      _file(
        'a.usfm',
        '\\id GEN\n'
            '\\c 1\n\\p\n\\v 28-29 a\n\\p\n\\v 29a b\n\\v 30 c\n'
            '\\c 2\n\\p\n\\v 29 a\n\\v 29a b\n'
            '\\c 3\n\\p\n\\v 1a a\n\\v 1b b\n\\v 1c c\n\\v 2 d\n'
            '\\c 4\n\\p\n\\v 5 a\n\\v 6a b\n\\v 10b-14 c\n\\v 6b-10a d\n'
            '\\c 5\n\\p\n\\v 1-6а а\n\\v 6б-11 б\n'
            '\\c 6\n\\p\n\\v 1-6 a\n\\v 6b b\n'
            '\\c 7\n\\p\n\\v 16 a\n\\v 13 b\n\\v 14 c\n'
            '\\c 8\n\\p\n\\v 5a-5b a\n\\v 6 b\n'
            '\\c 9\n\\p\n\\v 1 a\n\\v 1A b\n\\v 2 c\n',
      ),
    ]);
    final path = '${dir.path}/c.hb';

    writeUsfmModule(path, _meta('und'), books);

    expect(books.warnings, isEmpty);
    expect(checkModuleFile(path), isNull);
    final module = BibleModule.open(path);
    try {
      expect(
        [
          for (var chapter = 1; chapter <= 9; chapter++)
            [for (final v in module.chapter(10, chapter)) v.label],
        ],
        [
          ['28–29', '29a', '30'],
          ['29', '29a'],
          ['1a', '1b', '1c', '2'],
          ['5', '6a', '10b–14', '6b–10a'],
          ['1–6а', '6б–11'],
          ['1–6', '6b'],
          ['16', '13', '14'],
          ['5a', '6'],
          ['1', '1a', '2'],
        ],
      );
    } finally {
      module.close();
    }
  });
}
