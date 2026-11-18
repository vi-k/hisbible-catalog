import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:hisbible_format/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const ModuleMeta _meta = ModuleMeta(
  type: ModuleType.bible,
  abbreviation: 'TST',
  name: 'Test Bible',
  language: 'en',
  direction: WritingDirection.ltr,
  script: 'Latn',
  license: 'PD',
  copyright: 'Public Domain',
  description: 'A test translation.',
  source: 'ebible:engtst',
  sourceUrl: 'https://ebible.org/details.php?id=engtst',
  version: '2025-03-04',
  created: '2026-10-25',
  catalog: 'hisbible',
  catalogId: 'engtst',
  chapterWord: 'Chapter',
  chapterWordPsalms: 'Psalm',
  generator: 'test 0.1.0',
);

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hisbible_format_module_');
    path = '${dir.path}/TST.hb';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // Пишет образец: Бытие 1:1–2 и Псалом 3 с заголовками, сноской и слитыми
  // стихами 4–5.
  void writeSample(String path, {String genesisVerse2 = '<p/>And the earth'}) {
    ModuleWriter.create(path, _meta)
      ..addBook(
        number: 10,
        shortName: 'Gen',
        longName: 'Genesis',
        title: 'The First Book of Moses',
        scheme: VerseScheme.eng,
      )
      ..addBook(
        number: 230,
        shortName: 'Ps',
        longName: 'Psalms',
        scheme: VerseScheme.eng,
      )
      ..addVerse(10, 1, 1, 'In the beginning')
      ..addVerse(10, 1, 2, genesisVerse2)
      ..addVerse(230, 3, 1, 'Lord, how many')
      ..addVerse(230, 3, 2, 'Many say<f id="1" c="a"/>')
      ..addVerse(230, 3, 4, 'I cried', verseEnd: 5)
      ..addHeading(230, 3, 1, HeadingKind.title, 1, 'A Psalm of David')
      ..addHeading(230, 3, 1, HeadingKind.section, 2, 'Trust')
      ..addFootnote(1, 230, 3, 2, FootnoteKind.note, 'a', 'Or <em>soul</em>')
      ..finish();
  }

  test('writes and reads a bible', () {
    // Прежний файл на месте модуля заменяется.
    File(path).writeAsStringSync('old');
    writeSample(path);

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.meta, _meta);
    expect([for (final b in module.books) b.code], ['GEN', 'PSA']);
    final genesis = module.books.first;
    expect(genesis.number, 10);
    expect(genesis.shortName, 'Gen');
    expect(genesis.longName, 'Genesis');
    expect(genesis.title, 'The First Book of Moses');
    expect(genesis.chapters, [1]);
    expect(genesis.kind, BookKind.canonical);
    expect(genesis.scheme, VerseScheme.eng);
    final psalms = module.book(230)!;
    expect(psalms.code, 'PSA');
    expect(psalms.title, isNull);
    expect(psalms.chapters, [3]);
    expect(psalms.scheme, VerseScheme.eng);
    expect(module.book(470), isNull);
    expect(module.schemes.schemes, {10: VerseScheme.eng, 230: VerseScheme.eng});
    expect(module.schemes.uncertain, isEmpty);

    expect(module.chapter(230, 3), const [
      Verse(1, 'Lord, how many'),
      Verse(2, 'Many say<f id="1" c="a"/>'),
      Verse(4, 'I cried', verseEnd: 5),
    ]);
    expect(module.chapter(230, 4), isEmpty);
    expect(module.chapter(470, 1), isEmpty);
    expect(module.headings(230, 3), const [
      Heading(1, 0, HeadingKind.title, 1, 'A Psalm of David'),
      Heading(1, 1, HeadingKind.section, 2, 'Trust'),
    ]);
    expect(module.headings(10, 1), isEmpty);
    expect(module.footnotes(230, 3), const [
      Footnote(1, 230, 3, 2, FootnoteKind.note, 'a', 'Or <em>soul</em>'),
    ]);
    expect(module.lastVerses(), {
      10: {1: 2},
      230: {3: 5},
    });
    expect(module.hasParagraphMarks, isTrue);

    final plainPath = '${dir.path}/plain.hb';
    writeSample(plainPath, genesisVerse2: 'And the earth');
    final plain = BibleModule.open(plainPath);
    addTearDown(plain.close);
    expect(plain.hasParagraphMarks, isFalse);
  });

  test('a written book has a null color', () {
    writeSample(path);

    final db = sqlite3.open(path);
    final colors = [
      for (final row in db.select('SELECT color FROM books')) row['color'],
    ];
    expect(colors, [null, null]);

    // Файл со старым цветом открывается, книги на месте.
    db
      ..execute('UPDATE books SET color = 0xccccff')
      ..close();
    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect([for (final b in module.books) b.code], ['GEN', 'PSA']);
  });

  test('stamps format', () {
    writeSample(path);
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(db.close);
    expect(db.select('PRAGMA application_id').single.columnAt(0), 1214857833);
    expect(db.select('PRAGMA user_version').single.columnAt(0), 1);
    expect(formatApplicationId, 1214857833);
    expect(formatVersion, 1);
  });

  test('ignores unknown meta keys and tables', () {
    writeSample(path);
    sqlite3.open(path)
      ..execute("INSERT INTO meta VALUES ('future_key', 'v')")
      ..execute('CREATE TABLE future (a TEXT)')
      ..execute('ALTER TABLE verses ADD COLUMN future_column TEXT')
      ..close();

    expect(checkModuleFile(path), isNull);
    expect(readModuleMeta(path).extra, {'future_key': 'v'});
    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.meta.extra, {'future_key': 'v'});
    expect(module.meta.toValues()['future_key'], 'v');
    expect(module.chapter(10, 1), hasLength(2));
  });

  test('skips verses of books outside books table', () {
    ModuleWriter.create(path, _meta)
      ..addBook(
        number: 10,
        shortName: 'Gen',
        longName: 'Genesis',
        scheme: VerseScheme.eng,
      )
      ..addVerse(10, 1, 1, 'In the beginning')
      ..addVerse(470, 1, 1, 'The book of the genealogy')
      ..finish();
    // Книга с кодом, которого справочник не знает, тоже пропускается.
    sqlite3.open(path)
      ..execute(
        "INSERT INTO books VALUES (2, 'ZZZ', 'Z', 'Zzz', NULL, 'eng', NULL)",
      )
      ..execute("INSERT INTO verses VALUES ('ZZZ', 1, 1, NULL, 'z')")
      ..close();

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect([for (final b in module.books) b.number], [10]);
    expect(module.chapter(470, 1), isEmpty);
    expect(module.lastVerses(), {
      10: {1: 1},
    });
    expect(module.schemes.schemes.keys, [10]);
  });

  test('abort leaves no file', () {
    ModuleWriter.create(path, _meta)
      ..addBook(
        number: 10,
        shortName: 'Gen',
        longName: 'Genesis',
        scheme: VerseScheme.eng,
      )
      ..addVerse(10, 1, 1, 'In the beginning')
      ..abort();
    expect(File(path).existsSync(), isFalse);
  });

  test('intros are read in order and empty without the table', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(500, 'Ман', title: 'Молитва Манассии')],
      verses: const {(500, 1, 1): 'Господи'},
      intros: const [
        (500, IntroKind.title, 'Т'),
        (500, IntroKind.paragraph, 'А <f id="7" c="*"/>'),
      ],
      footnotes: const [Footnote(7, 500, 0, 0, FootnoteKind.note, '*', 'С')],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.intros(500), const [
      Intro(0, IntroKind.title, 'Т'),
      Intro(1, IntroKind.paragraph, 'А <f id="7" c="*"/>'),
    ]);
    expect(module.intros(10), isEmpty);
    expect(module.footnotes(500, 0), const [
      Footnote(7, 500, 0, 0, FootnoteKind.note, '*', 'С'),
    ]);

    // Модуль без таблицы `intros` читается, вступлений в нём нет.
    final plainPath = '${dir.path}/plain.hb';
    writeSample(plainPath);
    final plain = BibleModule.open(plainPath);
    addTearDown(plain.close);
    expect(plain.intros(10), isEmpty);
    expect(plain.preface(), isEmpty);
    expect(plain.prefaceArticles(), isEmpty);
  });

  test('the preface is read apart from the intros of books', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале'},
      intros: const [(10, IntroKind.paragraph, 'Книга')],
      preface: const [
        (IntroKind.title, 'Предисловие'),
        (IntroKind.paragraph, 'Дорогой читатель!'),
      ],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.preface(), const [
      Intro(0, IntroKind.title, 'Предисловие'),
      Intro(1, IntroKind.paragraph, 'Дорогой читатель!'),
    ]);
    expect(module.intros(10), const [Intro(0, IntroKind.paragraph, 'Книга')]);
    expect(module.books.map((book) => book.number), [10]);
  });

  test('the preface is split into articles', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале'},
      preface: const [
        (IntroKind.paragraph, 'Титул'),
        (IntroKind.article, 'Слово к <i>читателю</i>'),
        (IntroKind.paragraph, 'Книга'),
        (IntroKind.article, 'Послесловие'),
        (IntroKind.title, 'Часть I'),
      ],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.prefaceArticles(), const [
      PrefaceArticle(null, [Intro(0, IntroKind.paragraph, 'Титул')]),
      PrefaceArticle('Слово к <i>читателю</i>', [
        Intro(2, IntroKind.paragraph, 'Книга'),
      ]),
      PrefaceArticle('Послесловие', [Intro(4, IntroKind.title, 'Часть I')]),
    ]);
  });

  test('an author part names the author of its article', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале'},
      preface: const [
        (IntroKind.article, 'Слово'),
        (IntroKind.author, 'Митрополит Владимир'),
        (IntroKind.paragraph, 'Книга'),
        (IntroKind.article, 'Послесловие'),
        (IntroKind.paragraph, 'Прошло'),
      ],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.prefaceArticles(), const [
      PrefaceArticle('Слово', [
        Intro(2, IntroKind.paragraph, 'Книга'),
      ], author: 'Митрополит Владимир'),
      PrefaceArticle('Послесловие', [Intro(4, IntroKind.paragraph, 'Прошло')]),
    ]);
  });

  test('footnotes of the preface are apart from footnotes of books', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале<f id="2" c="+"/>'},
      preface: const [(IntroKind.paragraph, 'Читатель<f id="1" c="1"/>')],
      footnotes: const [
        Footnote(1, 0, 0, 0, FootnoteKind.note, '1', 'предисловия'),
        Footnote(2, 10, 1, 1, FootnoteKind.note, '+', 'стиха'),
      ],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.prefaceFootnotes(), const [
      Footnote(1, 0, 0, 0, FootnoteKind.note, '1', 'предисловия'),
    ]);
    expect(module.footnotes(10, 1).map((note) => note.id), [2]);
    expect(module.footnotes(10, 0), isEmpty);
  });

  test('a preface without articles is one untitled article', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале'},
      preface: const [(IntroKind.paragraph, 'Дорогой читатель!')],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.prefaceArticles(), const [
      PrefaceArticle(null, [
        Intro(0, IntroKind.paragraph, 'Дорогой читатель!'),
      ]),
    ]);
  });

  test('schemes name the home of the prayer of manasseh', () {
    ManassehHome home(String name, Map<(int, int, int), String> verses) {
      final file = '${dir.path}/$name.hb';
      writeBibleFixture(
        file,
        books: [
          for (final book in {for (final (b, _, _) in verses.keys) b})
            FixtureBook(book, '$book'),
        ],
        verses: verses,
      );
      final module = BibleModule.open(file);
      addTearDown(module.close);

      return module.schemes.manasseh;
    }

    expect(
      home('ch36', {(140, 36, 1): 'а', (140, 36, 35): 'б'}),
      ManassehHome.chronicles36,
    );
    expect(
      home('book', {
        (140, 36, 1): 'а',
        (140, 36, 35): 'б',
        (145, 1, 1): 'в',
        (145, 1, 15): 'г',
      }),
      ManassehHome.book,
    );
    expect(
      home('ch37', {(140, 36, 23): 'а', (140, 37, 1): 'б', (140, 37, 12): 'в'}),
      ManassehHome.chronicles37,
    );
    expect(
      home('none', {(140, 36, 1): 'а', (140, 36, 23): 'б'}),
      ManassehHome.book,
    );
    expect(home('no2ch', {(10, 1, 1): 'а'}), ManassehHome.book);
  });

  test('verse labels are read by chapter and empty without the table', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(140, '2 Пар')],
      verses: const {
        (140, 36, 23): 'а',
        (140, 36, 24): 'б',
        (140, 36, 25): 'в',
        (140, 35, 1): 'г',
      },
      verseLabels: const [(140, 36, 25, ''), (140, 36, 24, 'а')],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.verseLabels(140, 36), const {24: 'а', 25: ''});
    expect(module.verseLabels(140, 36).keys, [24, 25]);
    expect(module.verseLabels(140, 35), isEmpty);
    expect(module.verseLabels(10, 1), isEmpty);

    // Модуль без таблицы `verse_labels` читается, меток в нём нет.
    final plainPath = '${dir.path}/plain.hb';
    writeSample(plainPath);
    final plain = BibleModule.open(plainPath);
    addTearDown(plain.close);
    expect(plain.verseLabels(10, 1), isEmpty);
  });

  test('verse numbers are read by chapter and empty without the table', () {
    writeBibleFixture(
      path,
      books: const [FixtureBook(470, 'Мф')],
      verses: const {(470, 1, 1): 'а', (470, 1, 6): 'б', (470, 2, 1): 'в'},
      verseNumbers: const [(470, 1, 6, '6б–11'), (470, 1, 1, '1–6а')],
    );

    final module = BibleModule.open(path);
    addTearDown(module.close);
    expect(module.verseNumbers(470, 1), const {1: '1–6а', 6: '6б–11'});
    expect(module.verseNumbers(470, 1).keys, [1, 6]);
    expect(module.verseNumbers(470, 2), isEmpty);
    expect(module.verseNumbers(10, 1), isEmpty);

    // Модуль без таблицы `verse_numbers` читается, номеров в нём нет.
    final plainPath = '${dir.path}/plain.hb';
    writeSample(plainPath);
    final plain = BibleModule.open(plainPath);
    addTearDown(plain.close);
    expect(plain.verseNumbers(10, 1), isEmpty);
  });

  test('replaceFootnotes swaps footnotes of a copy', () {
    writeSample(path);
    final copy = '${dir.path}/copy.hb';
    File(path).copySync(copy);

    replaceFootnotes(copy, const [
      Footnote(1, 230, 3, 2, FootnoteKind.crossref, '', 'Ps 4:1'),
      Footnote(7, 10, 1, 1, FootnoteKind.note, '*', 'Or <em>start</em>'),
    ]);

    expect(checkModuleFile(copy), isNull);
    final changed = BibleModule.open(copy);
    addTearDown(changed.close);
    expect(changed.footnotes(230, 3), const [
      Footnote(1, 230, 3, 2, FootnoteKind.crossref, '', 'Ps 4:1'),
    ]);
    expect(changed.footnotes(10, 1), const [
      Footnote(7, 10, 1, 1, FootnoteKind.note, '*', 'Or <em>start</em>'),
    ]);
    final original = BibleModule.open(path);
    addTearDown(original.close);
    expect(original.footnotes(230, 3), const [
      Footnote(1, 230, 3, 2, FootnoteKind.note, 'a', 'Or <em>soul</em>'),
    ]);
    expect(original.footnotes(10, 1), isEmpty);
  });
}
