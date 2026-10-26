import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:catalog_builder/catalog_builder.dart';
import 'package:crypto/crypto.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:hisbible_format/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_builder_test');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  File zip(Map<String, String> files) {
    final archive = Archive();
    for (final MapEntry(:key, :value) in files.entries) {
      archive.addFile(ArchiveFile.string(key, value));
    }

    return File(p.join(dir.path, 'test_usfm.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  }

  String out() => p.join(dir.path, 'out', 'test.hb');

  Built built(BuildOutcome outcome) => switch (outcome) {
    Built() => outcome,
    BuildFailed(:final reasons) => fail('build failed: $reasons'),
  };

  BuildOutcome build(
    EbibleTranslation t,
    File usfmZip, {
    Overrides overrides = const Overrides(),
  }) => buildModule(
    t,
    usfmZip,
    out(),
    overrides: overrides,
    now: DateTime.utc(2026, 10, 26),
  );

  test('builds a module', () {
    final outcome = build(
      _translation(ot: 31 + 26, nt: 112),
      zip({
        '02-GENtest.usfm': _usfm(
          'GEN',
          [31],
          fields:
              '\\h Genesis\n\\toc1 The First Book of Moses\n'
              '\\toc2 Genesis\n\\toc3 Gen\n\\cl Chapter\n',
          texts: {(1, 1): r'In the beginning\f + \ft First note.\f*'},
        ),
        '20-PSAtest.SFM': _usfm(
          'PSA',
          [6, 12, 8],
          fields: '\\h Psalms\n\\toc2 Psalms\n\\toc3 Ps\n',
          chapterStart: {3: '\\d A Psalm of David.\n'},
        ),
        '44-JHNtest.usfm': _usfm(
          'JHN',
          [51, 25, 36],
          fields: '\\h John\n\\toc2 John\n\\toc3 Jn\n',
          texts: {(3, 16): r'For God so loved\f + \ft Second note.\f*'},
        ),
        'copr.htm':
            '<p><a href="http://creativecommons.org/licenses/by-sa/4.0/"> '
            'CC BY-SA 4.0</a></p>',
        'keys.asc': 'not a book',
      }),
      overrides: Overrides.parse('{"abbreviations": {"eng-test": "TST"}}'),
    );

    final module = built(outcome);
    expect(module.path, out());
    final bytes = File(out()).readAsBytesSync();
    expect(module.size, bytes.length);
    expect(module.sha256, sha256.convert(bytes).toString());
    expect(module.books, (ot: 2, nt: 1, dc: 0));
    expect(module.warnings, isEmpty);

    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    final meta = bible.meta;
    expect(meta, module.meta);
    expect(meta.abbreviation, 'TST');
    expect(meta.name, 'Test Bible');
    expect(meta.description, 'A Bible for tests');
    expect(meta.language, 'en');
    expect(meta.direction, WritingDirection.ltr);
    expect(meta.script, 'Latn');
    expect(meta.license, 'CC-BY-SA-4.0');
    expect(meta.copyright, '© 2026 Tests');
    expect(meta.source, 'ebible:eng-test');
    expect(meta.sourceUrl, 'http://ebible.org/eng-test/');
    expect(meta.version, '2026-09-26');
    expect(meta.created, '2026-10-26');
    expect(meta.catalog, 'hisbible');
    expect(meta.catalogId, 'eng-test');
    expect(meta.chapterWord, 'Chapter');
    expect(meta.generator, 'catalog_builder $builderVersion');

    expect([for (final b in bible.books) b.code], ['GEN', 'PSA', 'JHN']);
    expect([for (final b in bible.books) b.shortName], ['Gen', 'Ps', 'Jn']);
    expect(
      [for (final b in bible.books) b.longName],
      ['Genesis', 'Psalms', 'John'],
    );
    expect(
      [for (final b in bible.books) b.title],
      ['The First Book of Moses', null, null],
    );
    expect([
      for (final b in bible.books) b.scheme,
    ], everyElement(VerseScheme.eng));

    final title = bible.headings(230, 3).single;
    expect(
      (title.verse, title.kind, title.text),
      (1, HeadingKind.title, 'A Psalm of David.'),
    );

    expect(bible.footnotes(10, 1).single.id, 1);
    final second = bible.footnotes(500, 3).single;
    expect((second.id, second.verse, second.text), (2, 16, 'Second note.'));
    expect(bible.chapter(500, 3)[15].text, contains('<f id="2"'));
  });

  test('the generator version is the package version', () async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:catalog_builder/catalog_builder.dart'),
    );
    final pubspec = File(
      p.join(p.dirname(p.dirname(library!.toFilePath())), 'pubspec.yaml'),
    ).readAsStringSync();
    expect(pubspec, contains('\nversion: $builderVersion\n'));
  });

  test('names fall back to the header and the catalog', () {
    final outcome = build(
      _translation(nt: 25 + 25),
      zip({
        'MAT.usfm': _usfm('MAT', [25], fields: '\\h Matthew\n'),
        'MRK.usfm': _usfm('MRK', [25]),
      }),
    );

    built(outcome);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    final mark = BookCatalog.byNumber(480)!;
    expect(
      [for (final b in bible.books) (b.shortName, b.longName, b.title)],
      [('Matthew', 'Matthew', null), (mark.enShort, mark.enLong, null)],
    );
    expect(bible.meta.abbreviation, 'eng-test');
    expect(bible.meta.chapterWord, isNull);
  });

  test('russian order for ru', () {
    final outcome = build(
      _translation(language: 'rus', nt: 32 + 26 + 27),
      zip({
        '75-ROMtest.usfm': _usfm('ROM', [32]),
        '74-ACTtest.usfm': _usfm('ACT', [26]),
        '90-JAStest.usfm': _usfm('JAS', [27]),
      }),
    );

    built(outcome);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.meta.language, 'ru');
    expect([for (final b in bible.books) b.code], ['ACT', 'JAS', 'ROM']);
  });

  test('other languages go by book number', () {
    final outcome = build(
      _translation(nt: 32 + 26 + 27),
      zip({
        '90-JAStest.usfm': _usfm('JAS', [27]),
        '75-ROMtest.usfm': _usfm('ROM', [32]),
        '74-ACTtest.usfm': _usfm('ACT', [26]),
      }),
    );

    built(outcome);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect([for (final b in bible.books) b.code], ['ACT', 'ROM', 'JAS']);
  });

  test('skips books without a number', () {
    final outcome = build(
      _translation(ot: 31),
      zip({
        'GEN.usfm': _usfm('GEN', [31]),
        'DAG.usfm': _usfm('DAG', [10]),
      }),
    );

    final module = built(outcome);
    expect(module.warnings, [contains('DAG')]);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect([for (final b in bible.books) b.code], ['GEN']);
  });

  test('dropped text and unknown markers are warnings', () {
    final outcome = build(
      _translation(ot: 31),
      zip({
        'GEN.usfm': _usfm(
          'GEN',
          [31],
          texts: {(1, 2): r'Two \zz odd\zz*'},
          chapterStart: {1: 'Lost text\n'},
        ),
      }),
    );

    expect(built(outcome).warnings, [
      'GEN: dropped fragments: 1',
      'GEN: unknown markers: zz',
    ]);
  });

  test('a repeated verse keeps the first copy', () {
    final outcome = build(
      _translation(ot: 2),
      zip({
        'GEN.usfm':
            '\\id GEN\n\\c 1\n\\s First\n\\v 1 One\n\\s Second\n'
            r'\v 2 Two\f + \ft Kept.\f*'
            '\n\\s Again\n'
            r'\v 1 Again\f + \ft Lost.\f*',
      }),
    );

    expect(built(outcome).warnings, ['GEN 1:1: repeated verse, skipped']);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(
      [for (final v in bible.chapter(10, 1)) v.text],
      ['One', 'Two<f id="1" c="a"/>'],
    );
    expect(
      [for (final h in bible.headings(10, 1)) (h.verse, h.text)],
      [(1, 'First'), (2, 'Second')],
    );
    expect([for (final f in bible.footnotes(10, 1)) f.text], ['Kept.']);
  });

  test('merged verses that reach the next verse or run far are one verse', () {
    final outcome = build(
      _translation(ot: 4),
      zip({
        'GEN.usfm':
            '\\id GEN\n\\c 1\n\\p\n\\v 1-3 One\n\\v 2 Two\n\\v 3-4 Three\n'
            '\\c 2\n\\p\n\\v 1-250 Long\n',
      }),
    );

    expect(built(outcome).warnings, [
      'GEN 1:1-3: reaches verse 2, written as one verse',
      'GEN 2:1-250: more than $maxVerseEndSpan verses, written as one verse',
    ]);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.chapter(10, 1), const [
      Verse(1, 'One'),
      Verse(2, 'Two'),
      Verse(3, 'Three', verseEnd: 4),
    ]);
    expect(bible.chapter(10, 2), const [Verse(1, 'Long')]);
  });

  test('public domain needs both copr.htm and the Copyright column', () {
    String license(String copyright) {
      final outcome = build(
        _translation(ot: 3, copyright: copyright),
        zip({
          'GEN.usfm': _usfm('GEN', [3]),
          'copr.htm': '<p>This Bible is in the Public Domain.</p>',
        }),
      );

      return built(outcome).meta.license;
    }

    expect(license('Public Domain'), 'PD');
    expect(license('© 2026 Tests'), 'redistributable');
  });

  test('an empty copy of a book does not hide the full one', () {
    final outcome = build(
      _translation(ot: 31),
      zip({
        'A-GEN.usfm': '\\id GEN\n',
        'B-GEN.usfm': _usfm('GEN', [31]),
      }),
    );

    expect(built(outcome).warnings, ['GEN: no verses in A-GEN.usfm, skipped']);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.book(10)!.chapters, [1]);
  });

  test('fails validation on missing verses', () {
    final outcome = build(
      _translation(ot: 100),
      zip({
        'GEN.usfm': _usfm('GEN', [30]),
      }),
    );

    expect(outcome, isA<BuildFailed>());
    expect((outcome as BuildFailed).reasons, [
      contains('Old Testament: 30 verses, OTverses 100'),
    ]);
    expect(File(out()).existsSync(), isFalse);
    expect(Directory(p.dirname(out())).listSync(), isEmpty);
  });

  test('fails without books', () {
    final outcome = build(_translation(), zip({'copr.htm': 'Public Domain'}));

    expect(outcome, isA<BuildFailed>());
    expect(File(out()).existsSync(), isFalse);
  });

  test('fails on a broken zip entry', () {
    final file = zip({
      'GEN.usfm': _usfm('GEN', [31]),
    });
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    // Сжатые данные первой записи идут за её заголовком.
    final nameLength = bytes[26] | bytes[27] << 8;
    final extraLength = bytes[28] | bytes[29] << 8;
    final start = 30 + nameLength + extraLength;
    bytes.fillRange(start, start + 40, 0xFF);
    file.writeAsBytesSync(bytes);

    final outcome = build(_translation(ot: 31), file);

    expect(outcome, isA<BuildFailed>());
    expect((outcome as BuildFailed).reasons, [contains('cannot read')]);
    expect(File(out()).existsSync(), isFalse);
  });

  test('fails a build that leaves markup in a verse', () {
    final outcome = build(
      _translation(ot: 1),
      zip({'GEN.usfm': '\\id GEN\n\\c 1\n\\v 1 God|strong="H430" created'}),
    );

    expect(outcome, isA<BuildFailed>());
    expect((outcome as BuildFailed).reasons, [contains('GEN 1:1')]);
    expect(File(out()).existsSync(), isFalse);
    expect(Directory(p.dirname(out())).listSync(), isEmpty);
  });

  test('fails on a broken zip', () {
    final file = File(p.join(dir.path, 'broken.zip'))
      ..writeAsStringSync('not a zip');
    final outcome = build(_translation(), file);

    expect(outcome, isA<BuildFailed>());
    expect(File(out()).existsSync(), isFalse);
  });

  test('a module within 2% of the counts passes', () {
    final path = p.join(dir.path, 'ok.hb');
    writeBibleFixture(
      path,
      books: [const FixtureBook(10, 'Gen')],
      verses: {for (var v = 1; v <= 98; v++) (10, 1, v): 'Verse $v'},
    );

    expect(validateModule(path, _translation(ot: 100)), isEmpty);
    expect(validateModule(path, _translation(ot: 101)), hasLength(1));
  });

  test('fails validation on leftover markers', () {
    final path = p.join(dir.path, 'markers.hb');
    writeBibleFixture(
      path,
      books: [const FixtureBook(10, 'Gen')],
      verses: {
        (10, 1, 1): r'In the \v 2 beginning',
        (10, 1, 2): 'God|strong="H430" created',
        (10, 1, 3): r'A lone \ 3 stays',
      },
    );

    expect(validateModule(path, _translation(ot: 3)), [
      allOf(
        contains('GEN 1:1'),
        contains('GEN 1:2'),
        isNot(contains('GEN 1:3')),
      ),
    ]);
  });

  test('fails validation on a gap between chapters', () {
    final path = p.join(dir.path, 'gap.hb');
    writeBibleFixture(
      path,
      books: [const FixtureBook(10, 'Gen')],
      verses: {(10, 1, 1): 'One', (10, 3, 1): 'Three'},
    );

    expect(validateModule(path, _translation(ot: 2)), [contains('GEN')]);
  });

  test('fails validation on a file that is not a module', () {
    final path = p.join(dir.path, 'junk.hb');
    File(path).writeAsStringSync('junk');

    expect(validateModule(path, _translation()), hasLength(1));
  });
}

EbibleTranslation _translation({
  String language = 'eng',
  int ot = 0,
  int nt = 0,
  String copyright = '© 2026 Tests',
}) => EbibleTranslation(
  languageCode: language,
  translationId: 'eng-test',
  languageName: 'English',
  languageNameInEnglish: 'English',
  title: 'Test Bible',
  description: 'A Bible for tests',
  redistributable: true,
  copyright: copyright,
  updateDate: '2026-09-26',
  publicationUrl: 'http://ebible.org/eng-test/',
  otVerses: ot,
  ntVerses: nt,
  dcVerses: 0,
  textDirection: WritingDirection.ltr,
  downloadable: true,
  shortTitle: 'Test',
  script: 'Latin',
);

// Книга USFM [code] с главами по [chapters] стихов; [texts] — свой текст
// стиха (глава, стих), [chapterStart] — строки сразу после `\c`.
String _usfm(
  String code,
  List<int> chapters, {
  String fields = '',
  Map<(int, int), String> texts = const {},
  Map<int, String> chapterStart = const {},
}) {
  final out = StringBuffer('\\id $code\n$fields');
  for (var c = 1; c <= chapters.length; c++) {
    out.write('\\c $c\n${chapterStart[c] ?? ''}\\p\n');
    for (var v = 1; v <= chapters[c - 1]; v++) {
      out.write('\\v $v ${texts[(c, v)] ?? 'Verse $c:$v.'}\n');
    }
  }

  return out.toString();
}
