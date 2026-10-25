import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/catalog_builder.dart';
import 'package:crypto/crypto.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _release = 'https://github.com/vi-k/hisbible-catalog/releases/download';

void main() {
  late Directory work;
  late FakePublisher publisher;
  late FakeFetcher fetcher;
  late List<Duration> pauses;

  setUp(() {
    work = Directory.systemTemp.createTempSync('catalog_run_test');
    addTearDown(() => work.deleteSync(recursive: true));
    publisher = FakePublisher();
    fetcher = FakeFetcher(publisher);
    pauses = [];
  });

  Future<CatalogRun> run(
    List<EbibleTranslation> translations, {
    CatalogRun? after,
    DateTime? now,
    Overrides overrides = const Overrides(),
    FontsLock fonts = FontsLock.empty,
    int? limit,
    bool keepFiles = false,
  }) => runCatalogBuild(
    pause: (duration) async => pauses.add(duration),
    translations: translations,
    previous: after?.index ?? CatalogIndex.empty(),
    lock: after?.lock ?? const SourcesLock({}),
    overrides: overrides,
    fetcher: fetcher,
    publisher: publisher,
    work: work,
    now: now ?? DateTime.utc(2026, 11),
    fonts: fonts,
    limit: limit,
    keepFiles: keepFiles,
  );

  // Файлы, оставшиеся в подкаталоге [dir] рабочего каталога.
  List<String> left(String dir) {
    final directory = Directory(p.join(work.path, dir));

    return directory.existsSync()
        ? [for (final f in directory.listSync()) p.basename(f.path)]
        : const [];
  }

  // Перевод [id] на eBible: архив с [verses] стихами Бытия 1.
  EbibleTranslation offer(
    String id, {
    String date = '2026-09-01',
    int verses = 3,
    int? expected,
    bool redistributable = true,
    bool downloadable = true,
  }) {
    fetcher.ebible[_ebible(id)] = _zip(id, date, verses);

    return _translation(
      id,
      date: date,
      ot: expected ?? verses,
      redistributable: redistributable,
      downloadable: downloadable,
    );
  }

  test('first build publishes all', () async {
    final a = offer('aaa');
    final b = offer('bbb', verses: 4);
    final closed = offer('ccc', redistributable: false);
    final hidden = offer('ddd', downloadable: false);
    final excluded = offer('eee');

    final result = await run(
      [b, closed, a, hidden, excluded],
      overrides: Overrides.parse(
        '{"abbreviations": {"bbb": "BBB"}, "exclude": ["eee"]}',
      ),
    );

    final index = result.index;
    expect(index.format, 1);
    expect(index.catalog, 'hisbible');
    expect(index.name, 'HisBible');
    expect(index.updated, '2026-11-01');
    expect(index.modules.map((m) => m.id), ['aaa', 'bbb']);
    expect(index.withdrawn, isEmpty);
    expect(index.fonts, isEmpty);

    expect(publisher.files('build-2026-11-01'), [
      'aaa-2026-09-01.hb',
      'bbb-2026-09-01.hb',
    ]);
    expect(publisher.files('sources-2026-11-01'), [
      'aaa-2026-09-01_usfm.zip',
      'bbb-2026-09-01_usfm.zip',
    ]);
    expect(publisher.prerelease, {'sources-2026-11-01'});
    expect(fetcher.calls, [_ebible('aaa'), _ebible('bbb')]);

    final module = index.modules.last;
    final bytes = publisher.releases['build-2026-11-01']!['bbb-2026-09-01.hb']!;
    expect(module.type, 'bible');
    expect(module.abbreviation, 'BBB');
    expect(module.name, 'Bible bbb');
    expect(module.description, 'About bbb');
    expect(module.language, 'en');
    expect(module.languageName, 'English (bbb)');
    expect(module.languageNameEnglish, 'English');
    expect(module.script, 'Latn');
    expect(module.direction, WritingDirection.ltr);
    expect(module.license, 'redistributable');
    expect(module.copyright, '© bbb');
    expect(module.books, (ot: 1, nt: 0, dc: 0));
    expect(module.size, bytes.length);
    expect(module.sha256, sha256.convert(bytes).toString());
    expect(module.url, '$_release/build-2026-11-01/bbb-2026-09-01.hb');
    expect(module.version, '2026-09-01');
    expect(module.moduleFormat, formatVersion);

    final source = result.lock.entries['bbb']!;
    expect(result.lock.entries.keys, unorderedEquals(['aaa', 'bbb']));
    expect(source.id, 'bbb');
    expect(source.updateDate, '2026-09-01');
    expect(source.release, 'sources-2026-11-01');
    expect(source.asset, 'bbb-2026-09-01_usfm.zip');
    expect(source.fetched, '2026-11-01');
    expect(
      source.sha256,
      sha256.convert(fetcher.ebible[_ebible('bbb')]!).toString(),
    );

    expect(result.report.built, ['aaa', 'bbb']);
    expect(result.report.unchanged, isEmpty);
    expect(result.report.failed, isEmpty);
    expect(result.deletions, isEmpty);
    expect(left('modules'), isEmpty, reason: 'removed after upload');
    expect(left('sources'), isEmpty, reason: 'removed after the build');
  });

  test('keepFiles leaves sources and modules in work', () async {
    await run([offer('aaa')], keepFiles: true);

    expect(left('modules'), ['aaa-2026-09-01.hb']);
    expect(left('sources'), ['aaa-2026-09-01_usfm.zip']);
  });

  test('unchanged translation is not rebuilt', () async {
    final translations = [offer('aaa'), offer('bbb')];
    final first = await run(translations);
    final fetched = fetcher.calls.length;
    final uploaded = publisher.uploads.length;

    final second = await run(
      translations,
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(fetcher.calls, hasLength(fetched));
    expect(publisher.uploads, hasLength(uploaded));
    expect(publisher.deletes, isEmpty);
    expect(second.deletions, isEmpty);
    expect(second.index.modules, first.index.modules);
    expect(second.index.updated, '2026-12-01');
    expect(second.lock, first.lock);
    expect(second.report.unchanged, ['aaa', 'bbb']);
    expect(second.report.built, isEmpty);
  });

  test('updated translation gets new version', () async {
    final first = await run([offer('aaa'), offer('bbb')]);

    final second = await run(
      [offer('aaa', date: '2026-10-15', verses: 5), offer('bbb')],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    final module = second.index.modules.first;
    expect(module.id, 'aaa');
    expect(module.version, '2026-10-15');
    expect(module.url, '$_release/build-2026-12-01/aaa-2026-10-15.hb');
    expect(module.sha256, isNot(first.index.modules.first.sha256));
    expect(second.index.modules.last, first.index.modules.last);
    expect(second.deletions, [
      (release: 'sources-2026-11-01', asset: 'aaa-2026-09-01_usfm.zip'),
      (release: 'build-2026-11-01', asset: 'aaa-2026-09-01.hb'),
    ]);
    expect(publisher.deletes, isEmpty, reason: 'the run deletes nothing');
    expect(await applyDeletions(second.deletions, publisher), isEmpty);
    expect(publisher.files('build-2026-11-01'), ['bbb-2026-09-01.hb']);
    expect(publisher.files('build-2026-12-01'), ['aaa-2026-10-15.hb']);
    expect(publisher.files('sources-2026-11-01'), ['bbb-2026-09-01_usfm.zip']);
    expect(publisher.files('sources-2026-12-01'), ['aaa-2026-10-15_usfm.zip']);
    expect(second.lock.entries['aaa']!.updateDate, '2026-10-15');
    expect(second.lock.entries['aaa']!.release, 'sources-2026-12-01');
    expect(second.report.built, ['aaa']);
    expect(second.report.unchanged, ['bbb']);
  });

  test('source copy reused for the same date', () async {
    final first = await run([offer('aaa', expected: 100)]);
    expect(first.index.modules, isEmpty);
    expect(first.report.failed.keys, ['aaa']);
    expect(first.lock.entries.keys, ['aaa']);
    fetcher.calls.clear();

    // Та же дата, в таблице исправлено число стихов.
    final second = await run(
      [_translation('aaa', date: '2026-09-01', ot: 3)],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(fetcher.calls, [
      Uri.parse('$_release/sources-2026-11-01/aaa-2026-09-01_usfm.zip'),
    ]);
    expect(second.index.modules.map((m) => m.id), ['aaa']);
    expect(second.lock, first.lock);
    expect(second.deletions, isEmpty);
    expect(publisher.files('sources-2026-12-01'), isEmpty);
    expect(publisher.files('build-2026-12-01'), ['aaa-2026-09-01.hb']);
  });

  test('source copy with another sha256 fails the module', () async {
    final first = await run([offer('aaa', expected: 100)]);
    publisher.releases['sources-2026-11-01']!['aaa-2026-09-01_usfm.zip'] = [
      1,
      2,
      3,
    ];

    final second = await run(
      [_translation('aaa', date: '2026-09-01', ot: 3)],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(second.index.modules, isEmpty);
    expect(second.report.failed['aaa'], [contains('sha256')]);
  });

  test('withdrawn translation leaves index and assets', () async {
    final first = await run([offer('aaa'), offer('bbb'), offer('ccc')]);

    final second = await run(
      [offer('aaa'), offer('ccc')],
      after: first,
      overrides: Overrides.parse('{"exclude": ["ccc"]}'),
      now: DateTime.utc(2026, 12),
    );

    expect(second.index.modules.map((m) => m.id), ['aaa']);
    expect(second.index.withdrawn, const [
      WithdrawnModule(
        id: 'bbb',
        abbreviation: 'bbb',
        name: 'Bible bbb',
        since: '2026-12-01',
      ),
      WithdrawnModule(
        id: 'ccc',
        abbreviation: 'ccc',
        name: 'Bible ccc',
        since: '2026-12-01',
      ),
    ]);
    expect(second.deletions, [
      (release: 'build-2026-11-01', asset: 'bbb-2026-09-01.hb'),
      (release: 'build-2026-11-01', asset: 'ccc-2026-09-01.hb'),
      (release: 'sources-2026-11-01', asset: 'bbb-2026-09-01_usfm.zip'),
      (release: 'sources-2026-11-01', asset: 'ccc-2026-09-01_usfm.zip'),
    ]);
    expect(publisher.deletes, isEmpty, reason: 'the run deletes nothing');
    expect(await applyDeletions(second.deletions, publisher), isEmpty);
    expect(publisher.files('build-2026-11-01'), ['aaa-2026-09-01.hb']);
    expect(publisher.files('sources-2026-11-01'), ['aaa-2026-09-01_usfm.zip']);
    expect(second.lock.entries.keys, ['aaa']);
    expect(second.report.withdrawn, ['bbb', 'ccc']);

    // Вернувшийся перевод уходит из отозванных.
    final third = await run(
      [offer('aaa'), offer('bbb')],
      after: second,
      now: DateTime.utc(2027),
    );
    expect(third.index.modules.map((m) => m.id), ['aaa', 'bbb']);
    expect(third.index.withdrawn.map((m) => m.id), ['ccc']);
    expect(third.index.withdrawn.single.since, '2026-12-01');
  });

  test('failed build keeps previous version', () async {
    final first = await run([offer('aaa')]);

    final second = await run(
      [offer('aaa', date: '2026-10-15', expected: 100)],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(second.index.modules, first.index.modules);
    expect(publisher.files('build-2026-11-01'), ['aaa-2026-09-01.hb']);
    expect(publisher.files('build-2026-12-01'), isEmpty);
    expect(second.deletions, [
      (release: 'sources-2026-11-01', asset: 'aaa-2026-09-01_usfm.zip'),
    ]);
    expect(second.report.failed['aaa'], isNotEmpty);
    expect(second.report.toMarkdown(), contains('aaa'));
    expect(
      File(p.join(work.path, 'modules', 'aaa-2026-10-15.hb')).existsSync(),
      isFalse,
    );

    // Следующий прогон пробует снова, с исходником из своей копии.
    fetcher.calls.clear();
    final third = await run(
      [_translation('aaa', date: '2026-10-15', ot: 3)],
      after: second,
      now: DateTime.utc(2027),
    );
    expect(fetcher.calls, [
      Uri.parse('$_release/sources-2026-12-01/aaa-2026-10-15_usfm.zip'),
    ]);
    expect(third.index.modules.single.version, '2026-10-15');
    expect(third.deletions, [
      (release: 'build-2026-11-01', asset: 'aaa-2026-09-01.hb'),
    ]);
  });

  test('retries of failed builds go after new ones', () async {
    final first = await run([offer('aaa', expected: 100)]);
    expect(first.report.failed.keys, ['aaa']);
    fetcher.calls.clear();

    final second = await run(
      [offer('aaa', expected: 100), offer('bbb'), offer('ccc')],
      after: first,
      now: DateTime.utc(2026, 12),
      limit: 2,
    );

    expect(second.index.modules.map((m) => m.id), ['bbb', 'ccc']);
    expect(fetcher.calls, [_ebible('bbb'), _ebible('ccc')]);
    expect(second.report.waiting, ['aaa']);
    expect(second.report.failed, isEmpty);

    // Места хватает — несобранный пробуется снова, последним.
    final third = await run(
      [offer('aaa', expected: 100), offer('bbb'), offer('ccc'), offer('ddd')],
      after: second,
      now: DateTime.utc(2027),
      limit: 2,
    );
    expect(third.report.built, ['ddd']);
    expect(third.report.failed.keys, ['aaa']);
    expect(third.report.waiting, isEmpty);
  });

  test('deletions round trip and apply through the publisher', () async {
    publisher.releases['build-2026-11-01'] = {
      'aaa.hb': const [1],
    };
    publisher.releases['sources-2026-11-01'] = {
      'aaa_usfm.zip': const [2],
    };
    const deletions = [
      (release: 'build-2026-11-01', asset: 'aaa.hb'),
      (release: 'build-2026-11-01', asset: 'gone.hb'),
      (release: 'build-2026-11-01', asset: 'locked.hb'),
      (release: 'sources-2026-11-01', asset: 'aaa_usfm.zip'),
    ];
    publisher.releases['build-2026-11-01']!['locked.hb'] = const [3];
    publisher.brokenDeletes.add('build-2026-11-01/locked.hb');
    final json = deletionsToJson(deletions);

    expect(parseDeletions(json), deletions);
    expect(json, startsWith('{\n  "deletions": [\n    {\n'));
    expect(parseDeletions(deletionsToJson(const [])), isEmpty);
    expect(() => parseDeletions('{"deletions": [1]}'), throwsFormatException);

    final problems = await applyDeletions(parseDeletions(json), publisher);

    expect(publisher.deletes, [
      'build-2026-11-01/aaa.hb',
      'build-2026-11-01/gone.hb',
      'build-2026-11-01/locked.hb',
      'sources-2026-11-01/aaa_usfm.zip',
    ]);
    expect(problems, [
      contains('locked.hb'),
    ], reason: 'a file already gone is not a problem');
    expect(publisher.files('build-2026-11-01'), ['locked.hb']);
    expect(publisher.files('sources-2026-11-01'), isEmpty);
  });

  test('transient upload failure is retried', () async {
    publisher.transient['aaa-2026-09-01_usfm.zip'] = 1;
    publisher.transient['aaa-2026-09-01.hb'] = 3;

    final result = await run([offer('aaa')]);

    expect(result.index.modules.map((m) => m.id), ['aaa']);
    expect(result.report.failed, isEmpty);
    expect(publisher.attempts, [
      ...List.filled(2, 'aaa-2026-09-01_usfm.zip'),
      ...List.filled(4, 'aaa-2026-09-01.hb'),
    ]);
    expect(pauses, hasLength(4));
    expect(pauses.every((d) => d > Duration.zero), isTrue);
  });

  test('permanent upload failure fails only its module', () async {
    final first = await run([offer('aaa'), offer('ccc')]);
    publisher.broken = (asset) =>
        asset == 'aaa-2026-10-15.hb' || asset == 'ccc-2026-10-15_usfm.zip';

    final second = await run(
      [
        offer('aaa', date: '2026-10-15'),
        offer('bbb'),
        offer('ccc', date: '2026-10-15'),
      ],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(publisher.attempts.where((a) => a == 'aaa-2026-10-15.hb'), [
      for (var i = 0; i < 4; i++) 'aaa-2026-10-15.hb',
    ]);
    expect(second.report.built, ['bbb']);
    expect(second.report.failed.keys, unorderedEquals(['aaa', 'ccc']));
    expect(second.report.failed['aaa'], [contains('aaa-2026-10-15.hb')]);
    expect(second.report.failed['ccc'], [contains('ccc-2026-10-15_usfm.zip')]);
    // Прежние записи остаются.
    final old = {for (final m in first.index.modules) m.id: m};
    final now = {for (final m in second.index.modules) m.id: m};
    expect(now['aaa'], old['aaa']);
    expect(now['ccc'], old['ccc']);
    expect(now.keys, unorderedEquals(['aaa', 'bbb', 'ccc']));
    // Исходник aaa выложен и записан; исходник ccc — нет.
    expect(second.lock.entries['aaa']!.updateDate, '2026-10-15');
    expect(second.lock.entries['ccc'], first.lock.entries['ccc']);
    expect(second.deletions, [
      (release: 'sources-2026-11-01', asset: 'aaa-2026-09-01_usfm.zip'),
    ]);
  });

  test('too many upload failures stop the run early', () async {
    publisher.broken = (asset) => asset.endsWith('.hb');
    final translations = [
      for (var i = 0; i < 23; i++) offer('t${'$i'.padLeft(2, '0')}'),
    ];

    final result = await run(translations);

    expect(result.report.failed, hasLength(uploadFailureLimit + 1));
    expect(result.report.waiting, ['t21', 't22']);
    expect(result.index.modules, isEmpty);
    expect(result.lock.entries, hasLength(uploadFailureLimit + 1));
    expect(
      result.report.toMarkdown(),
      contains('Stopped early: ${uploadFailureLimit + 1} uploads failed'),
    );
  });

  test('failed download keeps previous version', () async {
    final first = await run([offer('aaa')]);
    final updated = offer('aaa', date: '2026-10-15');
    fetcher.ebible.remove(_ebible('aaa'));

    final second = await run(
      [updated],
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(second.index.modules, first.index.modules);
    expect(second.lock, first.lock);
    expect(second.report.failed['aaa'], [contains('aaa_usfm.zip')]);
  });

  test('limit stops early', () async {
    final translations = [
      for (final id in ['eee', 'ddd', 'ccc', 'bbb', 'aaa']) offer(id),
    ];

    final first = await run(translations, limit: 2);

    expect(first.index.modules.map((m) => m.id), ['aaa', 'bbb']);
    expect(fetcher.calls, [_ebible('aaa'), _ebible('bbb')]);
    expect(first.report.waiting, ['ccc', 'ddd', 'eee']);

    final second = await run(translations, after: first, limit: 2);
    expect(second.index.modules.map((m) => m.id), ['aaa', 'bbb', 'ccc', 'ddd']);
    expect(second.report.unchanged, ['aaa', 'bbb']);
    expect(second.report.waiting, ['eee']);
  });

  test('release overflow splits at 900', () async {
    final translations = [
      for (var i = 0; i <= 900; i++) offer('t${'$i'.padLeft(3, '0')}'),
    ];

    final result = await run(translations);

    expect(publisher.files('build-2026-11-01'), hasLength(900));
    expect(publisher.files('build-2026-11-01-2'), ['t900-2026-09-01.hb']);
    expect(publisher.files('sources-2026-11-01'), hasLength(900));
    expect(publisher.files('sources-2026-11-01-2'), [
      't900-2026-09-01_usfm.zip',
    ]);
    expect(publisher.prerelease, {
      'sources-2026-11-01',
      'sources-2026-11-01-2',
    });
    expect(
      result.index.modules.last.url,
      '$_release/build-2026-11-01-2/t900-2026-09-01.hb',
    );
    expect(result.lock.entries['t900']!.release, 'sources-2026-11-01-2');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('release overflow counts files already there', () async {
    publisher.releases['build-2026-11-01'] = {
      for (var i = 0; i < 899; i++) 'old$i.hb': const [0],
    };

    await run([offer('aaa'), offer('bbb')]);

    expect(publisher.files('build-2026-11-01'), contains('aaa-2026-09-01.hb'));
    expect(publisher.files('build-2026-11-01-2'), ['bbb-2026-09-01.hb']);
  });

  test('publishes fonts from lock', () async {
    final ethiopic = [1, 2, 3, 4];
    final arabic = [5, 6, 7];
    publisher.releases['fonts'] = {'NotoSansEthiopic-Regular.ttf': ethiopic};
    fetcher.other[Uri.parse('https://example.org/arabic.ttf')] = arabic;
    final lock = FontsLock({
      'Ethi': LockedFont(
        script: 'Ethi',
        family: 'Noto Sans Ethiopic',
        sourceUrl: 'https://example.org/ethiopic.ttf',
        sha256: sha256.convert(ethiopic).toString(),
        license: 'OFL-1.1',
        asset: 'NotoSansEthiopic-Regular.ttf',
      ),
      'Arab': LockedFont(
        script: 'Arab',
        family: 'Noto Naskh Arabic',
        sourceUrl: 'https://example.org/arabic.ttf',
        sha256: sha256.convert(arabic).toString(),
        license: 'OFL-1.1',
        asset: 'NotoNaskhArabic-Regular.ttf',
      ),
    });

    final fonts = await publishFonts(
      lock,
      fetcher: fetcher,
      publisher: publisher,
      work: work,
    );

    expect(fetcher.calls, [Uri.parse('https://example.org/arabic.ttf')]);
    expect(publisher.uploads, ['fonts/NotoNaskhArabic-Regular.ttf']);
    expect(publisher.prerelease, isEmpty);
    expect(fonts, {
      'Arab': IndexFont(
        family: 'Noto Naskh Arabic',
        license: 'OFL-1.1',
        size: 3,
        sha256: sha256.convert(arabic).toString(),
        url: '$_release/fonts/NotoNaskhArabic-Regular.ttf',
      ),
      'Ethi': IndexFont(
        family: 'Noto Sans Ethiopic',
        license: 'OFL-1.1',
        size: 4,
        sha256: sha256.convert(ethiopic).toString(),
        url: '$_release/fonts/NotoSansEthiopic-Regular.ttf',
      ),
    });

    // Раздел шрифтов указателя — тот же.
    final result = await run([], fonts: lock);
    expect(result.index.fonts, fonts);

    // Чужая sha256 — ошибка прогона, шрифт не выложен.
    fetcher.other[Uri.parse('https://example.org/hebrew.ttf')] = [9];
    final wrong = FontsLock({
      'Hebr': LockedFont(
        script: 'Hebr',
        family: 'Noto Sans Hebrew',
        sourceUrl: 'https://example.org/hebrew.ttf',
        sha256: sha256.convert([8]).toString(),
        license: 'OFL-1.1',
        asset: 'NotoSansHebrew-Regular.ttf',
      ),
    });
    await expectLater(
      publishFonts(wrong, fetcher: fetcher, publisher: publisher, work: work),
      throwsA(isA<CatalogBuildException>()),
    );
    await expectLater(
      run([offer('aaa')], fonts: wrong),
      throwsA(isA<CatalogBuildException>()),
    );
    expect(
      publisher.files('fonts'),
      isNot(contains('NotoSansHebrew-Regular.ttf')),
    );
    expect(publisher.files('build-2026-11-01'), isEmpty);
  });

  test('report lists what happened', () async {
    final first = await run([offer('aaa'), offer('bbb')]);
    final second = await run(
      [offer('aaa'), offer('ccc', expected: 100), offer('ddd'), offer('eee')],
      after: first,
      now: DateTime.utc(2026, 12),
      limit: 2,
    );

    final text = second.report.toMarkdown();
    expect(text, startsWith('# Catalog build 2026-12-01\n'));
    expect(text, contains('- Built: 1\n'));
    expect(text, contains('- Unchanged: 1\n'));
    expect(text, contains('- Withdrawn: 1\n'));
    expect(text, contains('- Failed: 1\n'));
    expect(text, contains('- Waiting for the next run: 1\n'));
    expect(text, contains('`ddd`'));
    expect(text, contains('`bbb`'));
    expect(text, contains('### `ccc`'));
    expect(text, contains('- Release files to delete: 2\n'));
    expect(text, contains('`build-2026-11-01/bbb-2026-09-01.hb`'));
  });
}

Uri _ebible(String id) =>
    Uri.parse('https://ebible.org/Scriptures/${id}_usfm.zip');

EbibleTranslation _translation(
  String id, {
  required String date,
  required int ot,
  bool redistributable = true,
  bool downloadable = true,
}) => EbibleTranslation(
  languageCode: 'eng',
  translationId: id,
  languageName: 'English ($id)',
  languageNameInEnglish: 'English',
  title: 'Bible $id',
  description: 'About $id',
  redistributable: redistributable,
  copyright: '© $id',
  updateDate: date,
  publicationUrl: 'https://ebible.org/$id/',
  otVerses: ot,
  ntVerses: 0,
  dcVerses: 0,
  textDirection: WritingDirection.ltr,
  downloadable: downloadable,
  shortTitle: id,
  script: 'Latin',
);

// Архив USFM с одной главой Бытия из [verses] стихов.
List<int> _zip(String id, String date, int verses) {
  final usfm = StringBuffer('\\id GEN $id $date\n\\h Genesis\n\\c 1\n\\p\n');
  for (var v = 1; v <= verses; v++) {
    usfm.write('\\v $v Verse $v of $id.\n');
  }
  final archive = Archive()
    ..addFile(ArchiveFile.string('01-GEN$id.usfm', usfm.toString()));

  return ZipEncoder().encodeBytes(archive);
}

/// Выпуски в памяти: выпуск → файл → байты.
final class FakePublisher implements Publisher {
  /// Файлы выпусков.
  final releases = <String, Map<String, List<int>>>{};

  /// Выпуски, созданные как pre-release.
  final prerelease = <String>{};

  /// Выкладки: `<выпуск>/<файл>`.
  final uploads = <String>[];

  /// Удаления: `<выпуск>/<файл>`.
  final deletes = <String>[];

  /// Попытки выкладки по порядку, удачные и нет: имена файлов.
  final attempts = <String>[];

  /// Сколько раз ещё не выложится файл: имя → число неудач.
  final transient = <String, int>{};

  /// Файлы, которые не выкладываются никогда.
  bool Function(String asset) broken = (_) => false;

  /// Удаления, которые не удаются: `<выпуск>/<файл>`.
  final brokenDeletes = <String>{};

  /// Файлы выпуска [release] по алфавиту.
  List<String> files(String release) =>
      (releases[release]?.keys.toList() ?? <String>[])..sort();

  @override
  Future<Uri> upload(
    String release,
    File file, {
    bool prerelease = false,
  }) async {
    final asset = p.basename(file.path);
    attempts.add(asset);
    final left = transient[asset] ?? 0;
    if (left > 0 || broken(asset)) {
      transient[asset] = left - 1;
      throw PublishException('upload of $asset failed');
    }
    final files = releases.putIfAbsent(release, () {
      if (prerelease) {
        this.prerelease.add(release);
      }

      return {};
    });
    files[asset] = file.readAsBytesSync();
    uploads.add('$release/$asset');

    return Uri.parse('$_release/$release/$asset');
  }

  @override
  Future<void> deleteAsset(String release, String asset) async {
    deletes.add('$release/$asset');
    if (brokenDeletes.contains('$release/$asset')) {
      throw PublishException('cannot delete $asset');
    }
    // Как GhPublisher: файла уже нет — удалён.
    releases[release]?.remove(asset);
  }

  @override
  Future<int> assetCount(String release) async =>
      releases[release]?.length ?? 0;

  @override
  Future<Map<String, int>> assets(String release) async => {
    for (final MapEntry(:key, :value) in (releases[release] ?? {}).entries)
      key: value.length,
  };
}

/// Сеть в памяти: eBible, выпуски [publisher] и прочие адреса.
final class FakeFetcher implements Fetcher {
  /// Создаёт сеть поверх выпусков [publisher].
  FakeFetcher(this.publisher);

  /// Выпуски, видные по их адресам.
  final FakePublisher publisher;

  /// Архивы eBible по адресу.
  final ebible = <Uri, List<int>>{};

  /// Прочие файлы по адресу.
  final other = <Uri, List<int>>{};

  /// Все запросы по порядку.
  final calls = <Uri>[];

  @override
  Future<List<int>> get(Uri uri) async {
    calls.add(uri);
    final segments = uri.toString().startsWith(_release)
        ? uri.pathSegments.skip(4).toList()
        : const <String>[];
    final release = segments.length == 2
        ? publisher.releases[segments[0]]
        : null;
    final published = release?[segments[1]];
    final bytes = ebible[uri] ?? other[uri] ?? published;
    if (bytes == null) {
      throw FetchException(uri, 404);
    }

    return bytes;
  }
}
