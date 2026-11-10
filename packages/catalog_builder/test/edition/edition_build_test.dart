import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/src/edition/edition_build.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _copyright =
    'Текст — общественное достояние. '
    'Параллельные места — по изданию Московской Патриархии.';

// Бытие 1: 31 стих, как в обеих схемах, иначе схема не распознается.
final _gen = [
  r'\id GEN',
  r'\toc1 Бытие',
  r'\c 1',
  r'\p',
  r'\v 1 Вначале сотворил Бог небо и землю пред лицем\f + \ft примечание\f* Его.',
  r'\v 2 Земля же была что́ безвидна. \x - \xt Ин 1:3|link-href="JHN 1:3"\xt*\x*',
  for (var v = 3; v <= 31; v++) '\\v $v Стих $v.',
].join('\n');

final _psa = [
  r'\id PSA',
  r'\toc1 Псалтирь',
  r'\c 114',
  r'\d Аллилуия.',
  r'\q',
  r'\v 1 Сказал я.',
  for (var v = 2; v <= 9; v++) '\\v $v Стих $v.',
].join('\n');

final _man = [
  r'\id MAN',
  r'\toc1 Молитва Манассии',
  r'\c 1',
  r'\p',
  for (var v = 1; v <= 15; v++) '\\v $v Стих $v.',
].join('\n');

int _book(String code) => BookCatalog.numberOfCode(code)!;

void main() {
  late Directory root;
  late Directory dir;
  final now = DateTime.utc(2026, 11, 10);

  void write(String name, String text) =>
      File(p.join(dir.path, 'usfm', name)).writeAsStringSync(text);

  setUp(() {
    root = Directory.systemTemp.createTempSync('edition_build_test');
    addTearDown(() => root.deleteSync(recursive: true));
    dir = Directory(p.join(root.path, editionsDir, 'russyn'))
      ..createSync(recursive: true);
    Directory(p.join(dir.path, 'usfm')).createSync();
    File(p.join(dir.path, 'edition.json')).writeAsStringSync(
      jsonEncode({
        'id': 'russyn',
        'abbreviation': 'RST',
        'name': 'Синодальный перевод',
        'description': 'Русский синодальный перевод',
        'language': 'ru',
        'languageName': 'Русский',
        'languageNameEnglish': 'Russian',
        'script': 'Cyrl',
        'direction': 'ltr',
        'license': 'PD',
        'copyright': _copyright,
        'sourceUrl': 'https://example.org/russyn',
      }),
    );
    File(p.join(dir.path, 'spelling.tsv')).writeAsStringSync('лицем\tлицом\n');
    write('01-GEN.usfm', _gen);
    write('19-PSA.usfm', _psa);
    write('MAN.usfm', _man);
  });

  String out() => p.join(root.path, 'russyn.hb');

  Future<EditionOutcome> build() =>
      buildEdition(readEdition(dir), out(), version: '2026-11-10', now: now);

  test('builds a bible from an edition', () async {
    final outcome = await build();
    final meta = outcome.meta;
    expect(meta.type, ModuleType.bible);
    expect(meta.abbreviation, 'RST');
    expect(meta.language, 'ru');
    expect(meta.source, 'edition:russyn');
    expect(meta.license, 'PD');
    expect(meta.copyright, _copyright);
    expect(meta.catalogId, 'russyn');
    expect(meta.created, '2026-11-10');
    expect(outcome.books, (ot: 2, nt: 0, dc: 1));
    expect(outcome.verses, 31 + 9 + 15);
    expect(File(out()).existsSync(), isTrue);
    expect(File('${out()}.part').existsSync(), isFalse);
  });

  test('applies spelling', () async {
    final outcome = await build();
    expect(outcome.replaced, 1);
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.chapter(_book('GEN'), 1)[0].text, contains('лицом'));
    expect(bible.chapter(_book('GEN'), 1)[0].text, isNot(contains('лицем')));
  });

  test('keeps stress marks', () async {
    await build();
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.chapter(_book('GEN'), 1)[1].text, contains('что́'));
  });

  test('notes and cross references', () async {
    final outcome = await build();
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    final notes = bible.footnotes(_book('GEN'), 1);
    expect(notes.where((n) => n.kind == FootnoteKind.note), hasLength(1));
    final refs = notes.where((n) => n.kind == FootnoteKind.crossref).toList();
    expect(refs, hasLength(1));
    final links = parseMarkup(refs.single.text).whereType<CrossrefLink>();
    final start = links.single.target?.start;
    expect((start?.book, start?.chapter, start?.verse), (_book('JHN'), 1, 3));
    expect(outcome.links.unresolved, 0);
  });

  test('psalm title', () async {
    await build();
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    final titles = bible
        .headings(_book('PSA'), 114)
        .where((h) => h.kind == HeadingKind.title && h.verse == 1);
    expect(titles, isNotEmpty);
  });

  test('digest changes with any file', () {
    final before = editionDigest(dir);
    expect(editionDigest(dir), before);
    final tsv = File(p.join(dir.path, 'spelling.tsv'))
      ..writeAsStringSync('лицем\tлицом \n');
    expect(editionDigest(dir), isNot(before));
    tsv.writeAsStringSync('лицем\tлицом\n');
    expect(editionDigest(dir), before);
  });

  test('digest does not depend on the order files were written', () {
    final other = Directory(p.join(root.path, 'copy', 'usfm'))
      ..createSync(recursive: true);
    final base = other.parent.path;
    for (final name in [
      'usfm/MAN.usfm',
      'edition.json',
      'usfm/19-PSA.usfm',
      'spelling.tsv',
      'usfm/01-GEN.usfm',
    ]) {
      File(p.join(base, name))
          .writeAsBytesSync(File(p.join(dir.path, name)).readAsBytesSync());
    }
    expect(editionDigest(other.parent), editionDigest(dir));
  });

  test('reads editions and rejects a missing field', () {
    expect(scanEditions(root).editions.map((e) => e.id), ['russyn']);
    File(p.join(dir.path, 'edition.json')).writeAsStringSync('{"id":"x"}');
    expect(() => readEdition(dir), throwsA(isA<FormatException>()));
  });

  // Поле [key] в `edition.json` издания — [value].
  void setField(String key, Object value) {
    final file = File(p.join(dir.path, 'edition.json'));
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    file.writeAsStringSync(jsonEncode({...json, key: value}));
  }

  test('the folder name is the id', () {
    setField('id', 'russyn2');
    expect(
      () => readEdition(dir),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('russyn2'), contains('folder')),
        ),
      ),
    );
  });

  test('direction is ltr or rtl', () {
    setField('direction', 'rtl');
    expect(readEdition(dir).direction, 'rtl');
    setField('direction', 'RTL');
    expect(
      () => readEdition(dir),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('direction'),
        ),
      ),
    );
  });

  test('only .usfm and .sfm files of usfm/ are read and hashed', () async {
    final before = editionDigest(dir);
    write('.DS_Store', 'не USFM');
    write('notes.txt', r'\id EXO');
    expect(editionDigest(dir), before);
    write('02-EXO.SFM', [r'\id EXO', r'\c 1', r'\v 1 Стих.'].join('\n'));
    expect(editionDigest(dir), isNot(before));
    final outcome = await build();
    expect(outcome.books, (ot: 3, nt: 0, dc: 1));
  });

  test('a file that is not UTF-8 is named', () async {
    File(p.join(dir.path, 'usfm', '19-PSA.usfm'))
        .writeAsBytesSync([...utf8.encode(r'\id PSA \c 1 \v 1 '), 0xff, 0xfe]);
    await expectLater(
      build(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('19-PSA.usfm'), contains('UTF-8')),
        ),
      ),
    );
  });

  test('a skipped empty book is not lost text', () async {
    // Имя файла попадает в предупреждение разбора и похоже на потерю.
    write('00: unknown markers.usfm', [r'\id EXO', r'\c 1'].join('\n'));
    final outcome = await build();
    expect(outcome.warnings, contains(contains('EXO: no verses')));
  });

  test('a verse lost on the way fails the build', () async {
    write('01-GEN.usfm', _gen.replaceFirst(r'\v 3 ', r'\v 2 '));
    await expectLater(
      build(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('54 verses in the module, 55'),
        ),
      ),
    );
    expect(File(out()).existsSync(), isFalse);
  });

  test('meta is read back from the written file', () async {
    final outcome = await build();
    final bible = BibleModule.open(out());
    addTearDown(bible.close);
    expect(bible.meta, outcome.meta);
    expect(bible.meta.source, 'edition:russyn');
    expect(bible.meta.version, '2026-11-10');
    expect(bible.meta.catalogId, 'russyn');
    expect(bible.meta.direction, WritingDirection.ltr);
  });

  test('editions of the repository are readable', () {
    final scan = scanEditions(Directory(p.join('..', '..')));
    expect(scan.broken, isEmpty);
    expect(scan.editions.map((e) => e.id), contains('russyn'));
  });

  test('invalid edition leaves no file', () async {
    write('01-GEN.usfm', _gen.replaceFirst('Вначале', r'Вначале \zz'));
    await expectLater(build(), throwsA(isA<FormatException>()));
    expect(File(out()).existsSync(), isFalse);
    expect(File('${out()}.part').existsSync(), isFalse);
  });

  test('invalid edition names all reasons', () async {
    write('01-GEN.usfm', _gen.replaceFirst('Вначале', r'Вначале \zz'));
    write('19-PSA.usfm', _psa.replaceFirst('Сказал', 'Сказал <b'));
    await expectLater(
      build(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('GEN'), contains('PSA')),
        ),
      ),
    );
  });

  test('uncertain numbering scheme is a warning', () async {
    write(
      '01-GEN.usfm',
      [
        r'\id GEN',
        r'\toc1 Бытие',
        r'\c 1',
        for (var v = 1; v <= 7; v++) '\\v $v Стих $v.',
        r'\c 2',
        for (var v = 1; v <= 3; v++) '\\v $v Стих $v.',
      ].join('\n'),
    );
    final outcome = await build();
    expect(
      outcome.warnings,
      contains(
        'GEN: numbering scheme is uncertain: the best scheme matches '
        'fewer than 95% of chapters',
      ),
    );
    expect(File(out()).existsSync(), isTrue);
  });
}
