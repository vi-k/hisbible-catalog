import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:hisbible_format/src/module/module_check.dart';
import 'package:hisbible_format/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hisbible_format_check_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String fixture(String name) {
    final path = '${dir.path}/$name';
    writeBibleFixture(
      path,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {(10, 1, 1): 'В начале'},
    );

    return path;
  }

  ModuleProblem? openProblem(String path) {
    try {
      BibleModule.open(path).close();

      return null;
    } on ModuleOpenException catch (e) {
      return e.problem;
    }
  }

  test('accepts a written bible', () {
    final path = fixture('good.hb');
    expect(checkModuleFile(path), isNull);
    expect(openProblem(path), isNull);
    final meta = readModuleMeta(path);
    expect(meta.type, ModuleType.bible);
    expect(meta.language, 'ru');
  });

  test('rejects foreign and newer files', () {
    final text = '${dir.path}/text.hb';
    File(text).writeAsStringSync('not a database at all, just some text\n');
    expect(checkModuleFile(text), const NotSqlite());
    expect(openProblem(text), const NotSqlite());

    final empty = '${dir.path}/empty.hb';
    sqlite3.open(empty).close();
    expect(checkModuleFile(empty), const NotHisbibleModule());

    // Чужой модуль SQLite со своими таблицами, без подписи формата.
    final foreign = '${dir.path}/foreign.hb';
    sqlite3.open(foreign)
      ..execute('CREATE TABLE info (name TEXT, value TEXT)')
      ..execute('CREATE TABLE books (book_number NUMERIC, short_name TEXT)')
      ..execute(
        'CREATE TABLE verses (book_number NUMERIC, chapter NUMERIC, '
        'verse NUMERIC, text TEXT)',
      )
      ..execute("INSERT INTO verses VALUES (10, 1, 1, 'x')")
      ..close();
    expect(checkModuleFile(foreign), const NotHisbibleModule());
    expect(openProblem(foreign), const NotHisbibleModule());
    expect(
      () => readModuleMeta(foreign),
      throwsA(
        isA<ModuleOpenException>().having(
          (e) => e.problem,
          'problem',
          const NotHisbibleModule(),
        ),
      ),
    );

    final newer = fixture('newer.hb');
    sqlite3.open(newer)
      ..execute('PRAGMA user_version = 2')
      ..close();
    expect(checkModuleFile(newer), const NewerFormat(2));
    expect(openProblem(newer), const NewerFormat(2));

    final nameless = fixture('nameless.hb');
    sqlite3.open(nameless)
      ..execute("DELETE FROM meta WHERE key = 'name'")
      ..close();
    expect(checkModuleFile(nameless), const MissingMeta('name'));
    expect(openProblem(nameless), const MissingMeta('name'));

    final verseless = '${dir.path}/verseless.hb';
    writeBibleFixture(
      verseless,
      books: const [FixtureBook(10, 'Быт')],
      verses: const {},
    );
    expect(checkModuleFile(verseless), const EmptyModule());
    expect(openProblem(verseless), const EmptyModule());

    final tableless = fixture('tableless.hb');
    sqlite3.open(tableless)
      ..execute('DROP TABLE headings')
      ..close();
    expect(checkModuleFile(tableless), const MissingTable('headings'));
  });

  test('a crafted book code is a problem, not an exception', () {
    final path = fixture('crafted.hb');
    sqlite3.open(path)
      ..execute("UPDATE books SET code = 'H99999999999999999999'")
      ..execute("UPDATE verses SET book = 'H99999999999999999999'")
      ..close();

    expect(checkModuleFile(path), const EmptyModule());
    expect(openProblem(path), const EmptyModule());
  });

  test('opens untrusted files with defensive settings', () {
    final path = fixture('good.hb');
    final db = openModuleReadOnly(path);
    addTearDown(db.close);

    expect(db.select('PRAGMA trusted_schema').single.columnAt(0), 0);
    expect(db.select('PRAGMA query_only').single.columnAt(0), 1);
    expect(readCheckedMeta(db).type, ModuleType.bible);
    expect(checkModuleFile(path), isNull);
  });

  group('verse_end', () {
    // Пишет Бытие 1 со стихами [verses]: номер → последний из слитых.
    String bible(String name, Map<int, int?> verses) {
      final path = '${dir.path}/$name';
      final writer = ModuleWriter.create(path, fixtureMeta)
        ..addBook(
          number: 10,
          shortName: 'Быт',
          longName: 'Бытие',
          scheme: VerseScheme.eng,
        );
      for (final MapEntry(key: verse, value: end) in verses.entries) {
        writer.addVerse(10, 1, verse, 'Стих $verse', verseEnd: end);
      }
      writer.finish();

      return path;
    }

    test('more than $maxVerseEndSpan above its verse is a problem', () {
      for (final end in [3 + maxVerseEndSpan + 1, 1 << 31, 1 << 62]) {
        final path = bible('far-$end.hb', {1: null, 2: null, 3: end});

        expect(
          checkModuleFile(path),
          const VerseEndOutOfRange('GEN', 1, 3),
          reason: '$end',
        );
        expect(openProblem(path), const VerseEndOutOfRange('GEN', 1, 3));
      }
    });

    test('up to $maxVerseEndSpan above the last verse is read', () {
      final path = bible('near.hb', {1: null, 2: 2 + maxVerseEndSpan});
      expect(checkModuleFile(path), isNull);

      final module = BibleModule.open(path);
      addTearDown(module.close);
      expect(module.chapter(10, 1), const [
        Verse(1, 'Стих 1'),
        Verse(2, 'Стих 2', verseEnd: 2 + maxVerseEndSpan),
      ]);
      expect(module.lastVerses(), {
        10: {1: 2 + maxVerseEndSpan},
      });
    });

    test('reaching the next verse reads as one verse', () {
      final path = bible('overlap.hb', {
        1: 3, // заходит на стих 2
        2: 4, // кончается до стиха 5
        5: 2, // меньше своего стиха
        6: 6, // равен своему стиху
        7: 9, // последний в главе
      });
      expect(checkModuleFile(path), isNull);

      final module = BibleModule.open(path);
      addTearDown(module.close);
      expect(module.chapter(10, 1), const [
        Verse(1, 'Стих 1'),
        Verse(2, 'Стих 2', verseEnd: 4),
        Verse(5, 'Стих 5'),
        Verse(6, 'Стих 6'),
        Verse(7, 'Стих 7', verseEnd: 9),
      ]);
      expect(module.lastVerses(), {
        10: {1: 9},
      });
    });

    test('an overlapping end does not count as the last verse', () {
      final path = bible('overlap-last.hb', {1: 150, 2: null});
      expect(checkModuleFile(path), isNull);

      final module = BibleModule.open(path);
      addTearDown(module.close);
      expect(module.chapter(10, 1), const [
        Verse(1, 'Стих 1'),
        Verse(2, 'Стих 2'),
      ]);
      expect(module.lastVerses(), {
        10: {1: 2},
      });
    });

    test('a verse_end that is not an integer is skipped', () {
      final path = bible('text.hb', {1: null, 2: null});
      sqlite3.open(path)
        ..execute("UPDATE verses SET verse_end = 'x' WHERE verse = 1")
        ..execute('UPDATE verses SET verse_end = 1e300 WHERE verse = 2')
        ..close();
      expect(checkModuleFile(path), isNull);

      final module = BibleModule.open(path);
      addTearDown(module.close);
      expect(module.chapter(10, 1), const [
        Verse(1, 'Стих 1'),
        Verse(2, 'Стих 2'),
      ]);
      expect(module.lastVerses(), {
        10: {1: 2},
      });
    });
  });

  test('meta keys follow the format', () {
    const meta = ModuleMeta(
      type: ModuleType.crossReferences,
      abbreviation: 'OB',
      name: 'Open Bible',
      language: 'en',
      direction: WritingDirection.rtl,
      numbering: 'eng',
      extra: {'future_key': 'v'},
    );
    expect(meta.toValues(), {
      'type': 'crossreferences',
      'abbreviation': 'OB',
      'name': 'Open Bible',
      'language': 'en',
      'direction': 'rtl',
      'license': 'unknown',
      'numbering': 'eng',
      'future_key': 'v',
    });
    expect(ModuleMeta.fromValues(meta.toValues()), meta);
    expect(meta.copyWith(abbreviation: 'OB2').abbreviation, 'OB2');
    expect(meta.copyWith(abbreviation: 'OB2').name, 'Open Bible');
    expect(
      () => ModuleMeta.fromValues(Map.of(meta.toValues())..remove('direction')),
      throwsA(
        isA<ModuleOpenException>().having(
          (e) => e.problem,
          'problem',
          const MissingMeta('direction'),
        ),
      ),
    );
  });

  test('blank optional meta values are absent', () {
    const meta = ModuleMeta(
      type: ModuleType.bible,
      abbreviation: 'A',
      name: 'N',
      language: 'en',
      direction: WritingDirection.ltr,
      script: '',
      copyright: '  ',
      description: 'Text',
    );
    expect(meta.toValues(), {
      'type': 'bible',
      'abbreviation': 'A',
      'name': 'N',
      'language': 'en',
      'direction': 'ltr',
      'license': 'unknown',
      'description': 'Text',
    });
    final read = ModuleMeta.fromValues({
      ...meta.toValues(),
      'script': '',
      'source': ' ',
      'numbering': '',
    });
    expect(read.script, isNull);
    expect(read.source, isNull);
    expect(read.numbering, isNull);
    expect(read.description, 'Text');
    expect(read, meta);
  });
}
