import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
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
}
