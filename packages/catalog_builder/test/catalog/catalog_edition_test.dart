import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'catalog_run_test.dart' show FakeFetcher, FakePublisher, regenerated;

const _release = 'https://github.com/vi-k/hisbible-catalog/releases/download';

const _copyright =
    'Текст — общественное достояние. '
    'Параллельные места — по изданию Московской Патриархии.';

// Бытие 1: 31 стих, как в обеих схемах, иначе схема не распознается.
final _gen = [
  r'\id GEN',
  r'\toc1 Бытие',
  r'\c 1',
  r'\p',
  r'\v 1 Вначале сотворил Бог небо и землю пред лицем Его.',
  r'\v 2 Земля же была безвидна. \x - \xt Ин 1:3|link-href="JHN 1:3"\xt*\x*',
  for (var v = 3; v <= 31; v++) '\\v $v Стих $v.',
].join('\n');

final _psa = [
  r'\id PSA',
  r'\toc1 Псалтирь',
  r'\c 114',
  r'\d Аллилуия.',
  r'\q',
  for (var v = 1; v <= 9; v++) '\\v $v Стих $v.',
].join('\n');

final _man = [
  r'\id MAN',
  r'\toc1 Молитва Манассии',
  r'\c 1',
  r'\p',
  for (var v = 1; v <= 15; v++) '\\v $v Стих $v.',
].join('\n');

// Строка eBible `russyn`: её прогон не берёт, пока есть издание.
const _russynRow = EbibleTranslation(
  languageCode: 'rus',
  translationId: 'russyn',
  languageName: 'Русский',
  languageNameInEnglish: 'Russian',
  title: 'Russian Synodal Translation',
  description: 'Russian Synodal Translation',
  redistributable: true,
  copyright: 'Public Domain',
  updateDate: '2022-11-25',
  publicationUrl: 'https://ebible.org/russyn/',
  otVerses: 1,
  ntVerses: 0,
  dcVerses: 0,
  textDirection: WritingDirection.ltr,
  downloadable: true,
  shortTitle: 'russyn',
  script: 'Cyrillic',
);

// Прежняя запись `russyn` из eBible.
const _ebibleEntry = IndexModule(
  id: 'russyn',
  type: 'bible',
  source: 'ebible',
  abbreviation: 'RST',
  name: 'Russian Synodal Translation',
  language: 'ru',
  languageName: 'Русский',
  languageNameEnglish: 'Russian',
  script: 'Cyrl',
  direction: WritingDirection.ltr,
  license: 'PD',
  books: (ot: 39, nt: 27, dc: 0),
  size: 1,
  sha256: 'aa',
  url: '$_release/build-2026-10-01/russyn-2022-11-25.2.hb',
  version: '2022-11-25.2',
  moduleFormat: 1,
);

const _ebibleSource = LockedSource(
  id: 'russyn',
  updateDate: '2022-11-25',
  sha256: 'bb',
  release: 'sources-2026-10-01',
  asset: 'russyn-2022-11-25_usfm.zip',
  fetched: '2026-10-01',
);

const _ebibleIndex = CatalogIndex(
  format: catalogIndexFormat,
  catalog: 'hisbible',
  name: 'HisBible',
  updated: '2026-10-01',
  modules: [_ebibleEntry],
);

void main() {
  late Directory root;
  late Directory dir;
  late Directory work;
  late FakePublisher publisher;
  late FakeFetcher fetcher;
  final today = DateTime.utc(2026, 11, 10);

  void write(String name, String text) =>
      File(p.join(dir.path, 'usfm', name)).writeAsStringSync(text);

  // Папка издания [folder] с id [id] и книгами Бытия, Псалтири и Манассии.
  Directory edition(String folder, {String id = 'russyn'}) {
    final dir = Directory(p.join(root.path, editionsDir, folder))
      ..createSync(recursive: true);
    Directory(p.join(dir.path, 'usfm')).createSync();
    File(p.join(dir.path, 'edition.json')).writeAsStringSync(
      jsonEncode({
        'id': id,
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
    for (final (name, text) in [
      ('01-GEN.usfm', _gen),
      ('19-PSA.usfm', _psa),
      ('MAN.usfm', _man),
    ]) {
      File(p.join(dir.path, 'usfm', name)).writeAsStringSync(text);
    }

    return dir;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('catalog_edition_test');
    addTearDown(() => root.deleteSync(recursive: true));
    work = Directory(p.join(root.path, 'work'))..createSync();
    dir = edition('russyn');
    publisher = FakePublisher();
    fetcher = FakeFetcher(publisher);
  });

  // Прогон с изданиями из [root] поверх прежнего прогона [after] или
  // указателя с записью `russyn` из eBible.
  Future<CatalogRun> run({
    CatalogRun? after,
    DateTime? now,
    List<EbibleTranslation>? translations,
    int? limit,
    Set<String> rebuild = const {},
    String? rebuildBefore,
  }) => runCatalogBuild(
    pause: (_) async {},
    translations: translations ?? [_russynRow],
    previous: after?.index ?? _ebibleIndex,
    lock: after?.lock ?? const SourcesLock({'russyn': _ebibleSource}),
    pending: after?.deletions ?? const [],
    editions: scanEditions(root).editions,
    brokenEditions: scanEditions(root).broken,
    editionDigests: after?.editionDigests ?? const {},
    overrides: Overrides.parse('{"abbreviations": {"russyn": "RST"}}'),
    fetcher: fetcher,
    publisher: publisher,
    work: work,
    now: now ?? today,
    limit: limit,
    rebuild: rebuild,
    rebuildBefore: rebuildBefore,
    clock: () => now ?? today,
  );

  IndexModule entry(CatalogRun result) =>
      result.index.modules.singleWhere((m) => m.id == 'russyn');

  test('edition replaces the eBible module in place', () async {
    final result = await run();

    final module = entry(result);
    expect(result.index.modules, hasLength(1));
    expect(module.source, 'edition');
    expect(module.type, 'bible');
    expect(module.version, '2026-11-10');
    expect(module.url, '$_release/build-2026-11-10/russyn-2026-11-10.hb');
    expect(module.abbreviation, 'RST');
    expect(module.name, 'Синодальный перевод');
    expect(module.description, 'Русский синодальный перевод');
    expect(module.language, 'ru');
    expect(module.languageName, 'Русский');
    expect(module.languageNameEnglish, 'Russian');
    expect(module.script, 'Cyrl');
    expect(module.license, 'PD');
    expect(module.copyright, _copyright);
    expect(module.books, (ot: 2, nt: 0, dc: 1));
    expect(module.moduleFormat, formatVersion);
    final bytes =
        publisher.releases['build-2026-11-10']!['russyn-2026-11-10.hb']!;
    expect(module.size, bytes.length);

    expect(result.index.withdrawn, isEmpty);
    expect(result.report.withdrawn, isEmpty);
    expect(result.report.built, ['russyn']);
    expect(result.report.failed, isEmpty);
    expect(
      result.deletions,
      unorderedEquals([
        (release: 'build-2026-10-01', asset: 'russyn-2022-11-25.2.hb'),
        (release: 'sources-2026-10-01', asset: 'russyn-2022-11-25_usfm.zip'),
      ]),
    );
    expect(result.lock.entries.containsKey('russyn'), isFalse);
    expect(fetcher.calls, isEmpty, reason: 'the eBible row is not taken');
    expect(publisher.files('build-2026-11-10'), ['russyn-2026-11-10.hb']);
    expect(publisher.releases.keys, ['build-2026-11-10']);
    expect(result.editionDigests, {'russyn': editionDigest(dir)});
    expect(Directory(p.join(work.path, 'modules')).listSync(), isEmpty);
  });

  test('the report has a line for the edition', () async {
    final text = (await run()).report.toMarkdown();

    expect(text, contains('\n## Editions\n'));
    expect(
      text,
      matches(
        RegExp(
          '- `russyn`: verses 55, replaced 1, links 1, unresolved 0, '
          r'schemes (rsc|rso) \d+',
        ),
      ),
    );
  });

  test('edition warnings go under its line in the report', () async {
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

    final text = (await run()).report.toMarkdown();

    expect(
      text,
      matches(
        RegExp(
          r'- `russyn`: verses \d+, [^\n]*\n'
          '  - GEN: numbering scheme is uncertain',
        ),
      ),
    );
  });

  test('editions do not count against the limit', () async {
    final result = await run(limit: 0);

    expect(result.report.built, ['russyn']);
    expect(result.report.waiting, isEmpty);
  });

  test('unchanged edition is not rebuilt', () async {
    final first = await run();
    final uploads = publisher.uploads.length;

    final second = await run(after: first, now: DateTime.utc(2026, 12));

    expect(entry(second), entry(first));
    expect(second.index, first.index);
    expect(publisher.uploads, hasLength(uploads));
    expect(second.report.unchanged, ['russyn']);
    expect(second.report.built, isEmpty);
    expect(second.deletions, isEmpty);
    expect(second.editionDigests, first.editionDigests);
    expect(second.lock.entries.containsKey('russyn'), isFalse);
  });

  test('changed edition gets a new revision the same day', () async {
    final first = await run();
    write('MAN.usfm', _man.replaceFirst('Стих 1.', 'Стих первый.'));

    final second = await run(after: first);

    final module = entry(second);
    expect(module.version, '2026-11-10.1');
    expect(module.url, '$_release/build-2026-11-10/russyn-2026-11-10.1.hb');
    expect(module.source, 'edition');
    expect(second.report.built, ['russyn']);
    expect(second.deletions, [
      (release: 'build-2026-11-10', asset: 'russyn-2026-11-10.hb'),
    ]);
    expect(second.editionDigests, {'russyn': editionDigest(dir)});
    expect(second.editionDigests, isNot(first.editionDigests));
  });

  test('edition is not withdrawn when eBible drops russyn', () async {
    final first = await run();

    final second = await run(
      after: first,
      translations: const [],
      now: DateTime.utc(2026, 12),
    );

    expect(entry(second), entry(first));
    expect(second.index.withdrawn, isEmpty);
    expect(second.report.withdrawn, isEmpty);
    expect(second.deletions, isEmpty);
  });

  test(
    'without an earlier run the eBible withdrawal does not hit it',
    () async {
      write('MAN.usfm', _man.replaceFirst(r'\p', r'\p \zz'));

      final result = await run(translations: const []);

      expect(entry(result), _ebibleEntry, reason: 'the failed build keeps it');
      expect(result.index.withdrawn, isEmpty);
    },
  );

  test('rebuild by id works for an edition', () async {
    final first = await run();

    final second = await run(after: first, rebuild: {'russyn'});

    expect(entry(second).version, '2026-11-10.1');
    expect(second.report.built, ['russyn']);
    expect(second.report.failed, isEmpty);
    expect(second.report.rebuildMissed, isEmpty);
  });

  test('rebuild-before works for an edition', () async {
    final first = await run();

    final second = await run(
      after: first,
      now: DateTime.utc(2026, 12),
      rebuildBefore: '2026-12-01',
    );

    expect(entry(second).version, '2026-12-01');
    expect(
      entry(second).url,
      '$_release/build-2026-12-01/russyn-2026-12-01.hb',
    );
    expect(second.report.built, ['russyn']);
  });

  test('an edition of another builder version is rebuilt', () async {
    final first = await run();
    expect(entry(first).generator, currentGenerator);

    for (final generator in ['catalog_builder 0.2.0', null]) {
      final second = await run(
        after: regenerated(first, generator),
        now: DateTime.utc(2026, 12),
      );

      expect(second.report.built, ['russyn'], reason: '$generator');
      expect(entry(second).version, '2026-12-01');
      expect(entry(second).generator, currentGenerator);
    }

    final same = await run(after: first, now: DateTime.utc(2026, 12));
    expect(same.report.built, isEmpty);
    expect(same.report.unchanged, ['russyn']);
    expect(entry(same), entry(first));
  });

  test('a failed edition keeps the previous entry', () async {
    write('MAN.usfm', _man.replaceFirst(r'\p', r'\p \zz'));

    final result = await run();

    expect(entry(result), _ebibleEntry);
    expect(result.index.withdrawn, isEmpty);
    expect(result.report.built, isEmpty);
    expect(result.report.failed['russyn'], isNotEmpty);
    expect(result.lock.entries['russyn'], _ebibleSource);
    expect(result.deletions, isEmpty);
    expect(result.editionDigests, isEmpty);
    expect(publisher.uploads, isEmpty);
  });

  test('a failed or broken edition makes the run red', () async {
    write('MAN.usfm', _man.replaceFirst(r'\p', r'\p \zz'));
    final abc = edition('abc', id: 'abc');
    File(p.join(abc.path, 'edition.json')).writeAsStringSync('{');

    final result = await run();

    expect(result.report.editionsFailed, ['abc', 'russyn']);
    expect(catalogExitCode(result.report), redRunExitCode);
    expect(
      result.report.toMarkdown(),
      contains('**Edition not built: abc, russyn'),
    );
    expect(entry(result), _ebibleEntry, reason: 'the old entry stays');

    write('MAN.usfm', _man);
    File(p.join(abc.path, 'edition.json')).deleteSync();
    abc.deleteSync(recursive: true);
    final fixed = await run(after: result);
    expect(fixed.report.editionsFailed, isEmpty);
    expect(catalogExitCode(fixed.report), 0);
  });

  test('the edition version never goes below the previous one', () async {
    // Прежняя запись с датой позже даты прогона.
    const later = IndexModule(
      id: 'russyn',
      type: 'bible',
      source: 'ebible',
      abbreviation: 'RST',
      name: 'Russian Synodal Translation',
      language: 'ru',
      languageName: 'Русский',
      languageNameEnglish: 'Russian',
      script: 'Cyrl',
      direction: WritingDirection.ltr,
      license: 'PD',
      books: (ot: 39, nt: 27, dc: 0),
      size: 1,
      sha256: 'aa',
      url: '$_release/build-2026-10-01/russyn-2026-11-20.hb',
      version: '2026-11-20',
      moduleFormat: 1,
    );
    final result = await runCatalogBuild(
      pause: (_) async {},
      translations: [_russynRow],
      previous: const CatalogIndex(
        format: catalogIndexFormat,
        catalog: 'hisbible',
        name: 'HisBible',
        updated: '2026-10-01',
        modules: [later],
      ),
      lock: const SourcesLock({'russyn': _ebibleSource}),
      editions: scanEditions(root).editions,
      overrides: const Overrides(),
      fetcher: fetcher,
      publisher: publisher,
      work: work,
      now: today,
      clock: () => today,
    );

    expect(entry(result).version, '2026-11-20.1');
  });

  test('a failed rebuild keeps the previous digest', () async {
    final first = await run();
    write('MAN.usfm', _man.replaceFirst(r'\p', r'\p \zz'));

    final second = await run(after: first);

    expect(entry(second), entry(first));
    expect(second.editionDigests, first.editionDigests);
    expect(second.report.failed['russyn'], isNotEmpty);
  });

  test('a broken edition folder does not stop the run', () async {
    File(p.join(dir.path, 'edition.json')).writeAsStringSync('{');
    edition('abc', id: 'abc');

    final result = await run();

    expect(entry(result), _ebibleEntry);
    expect(result.lock.entries['russyn'], _ebibleSource);
    expect(result.index.withdrawn, isEmpty);
    expect(result.report.withdrawn, isEmpty);
    expect(fetcher.calls, isEmpty, reason: 'the eBible row is not taken');
    expect(result.report.failed['russyn'], isNotEmpty);
    expect(result.report.built, ['abc']);
    expect(result.editionDigests.keys, ['abc']);
    expect(
      result.report.toMarkdown(),
      matches(
        RegExp(
          '- `russyn`: not built\n'
          r'  - [^\n]*edition\.json',
        ),
      ),
    );
  });

  test('a broken edition keeps its built entry and digest', () async {
    final first = await run();
    Directory(p.join(dir.path, 'usfm')).deleteSync(recursive: true);

    final second = await run(after: first, translations: const []);

    expect(entry(second), entry(first));
    expect(second.editionDigests, first.editionDigests);
    expect(second.index.withdrawn, isEmpty);
    expect(second.deletions, isEmpty);
    expect(second.report.failed['russyn'], isNotEmpty);
  });

  test('a broken folder is named by its declared id or folder name', () {
    Directory(p.join(dir.path, 'usfm')).deleteSync(recursive: true);
    final other = edition('other', id: 'abc');
    File(p.join(other.path, 'edition.json')).writeAsStringSync('[');

    final scan = scanEditions(root);

    expect(scan.editions, isEmpty);
    expect(scan.broken.keys, unorderedEquals(['russyn', 'other']));
    expect(scan.broken['russyn'], contains('usfm'));
  });

  test('two editions with the same id are both failures', () async {
    edition('russyn-copy');

    final result = await run();

    expect(entry(result), _ebibleEntry);
    expect(result.lock.entries['russyn'], _ebibleSource);
    expect(result.report.built, isEmpty);
    expect(publisher.uploads, isEmpty);
    expect(fetcher.calls, isEmpty, reason: 'the eBible row is not taken');
    expect(result.report.failed['russyn']!.join(), contains('russyn-copy'));
    expect(result.report.toMarkdown(), contains('- `russyn`: not built\n'));

    final dropped = await run(translations: const []);
    expect(entry(dropped), _ebibleEntry, reason: 'not withdrawn');
    expect(dropped.index.withdrawn, isEmpty);
  });

  test('editions lock round trips', () {
    const lock = {'russyn': 'cc', 'abc': 'dd'};
    final json = editionsLockToJson(lock);

    expect(parseEditionsLock(json), lock);
    expect(
      json,
      '{\n  "abc": {\n    "digest": "dd"\n  },\n'
      '  "russyn": {\n    "digest": "cc"\n  }\n}\n',
    );
    expect(() => parseEditionsLock('[]'), throwsFormatException);
    expect(
      () => parseEditionsLock('{"russyn": {"digest": 1}}'),
      throwsFormatException,
    );
  });
}
