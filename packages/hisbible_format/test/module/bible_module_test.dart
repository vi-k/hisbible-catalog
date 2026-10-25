import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
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
        scheme: VerseScheme.org,
        color: 0x66ff99,
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
    expect(genesis.color, isNull);
    expect(genesis.chapters, [1]);
    expect(genesis.kind, BookKind.canonical);
    expect(genesis.scheme, VerseScheme.eng);
    final psalms = module.book(230)!;
    expect(psalms.code, 'PSA');
    expect(psalms.title, isNull);
    expect(psalms.color, 0x66ff99);
    expect(psalms.chapters, [3]);
    expect(psalms.scheme, VerseScheme.org);
    expect(module.book(470), isNull);
    expect(module.schemes.schemes, {10: VerseScheme.eng, 230: VerseScheme.org});
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
