import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:crypto/crypto.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../crosswire/zcom_fixture.dart';
import 'catalog_run_test.dart' show FakeFetcher, FakePublisher;

const _release = 'https://github.com/vi-k/hisbible-catalog/releases/download';

// Архив Clarke с толкованиями Бытия 1:1 и Матфея 1:1; [extra] меняет
// архив при той же `SwordVersionDate`.
List<int> _clarke({String version = '2021-10-19', String extra = ''}) =>
    crosswireZip(
      'Clarke',
      (ZComFixture()
            ..put('Gen', 1, 1, '<hi type="bold">Verse 1</hi> Beginning.$extra')
            ..put('Matt', 1, 1, '<hi type="bold">Verse 1</hi> The book.'))
          .files(),
      version: version,
    );

CrossWireSource _locked(List<int> zip, {String version = '2021-10-19'}) =>
    CrossWireSource(
      url: crosswireUrl('Clarke').toString(),
      sha256: sha256.convert(zip).toString(),
      version: version,
      fetched: '2026-10-30',
    );

void main() {
  late Directory work;
  late FakePublisher publisher;
  late FakeFetcher fetcher;
  final clarkeUrl = crosswireUrl('Clarke');
  const id = 'crosswire-clarke';

  setUp(() {
    work = Directory.systemTemp.createTempSync('catalog_crosswire_test');
    addTearDown(() => work.deleteSync(recursive: true));
    publisher = FakePublisher();
    fetcher = FakeFetcher(publisher);
  });

  // Прогон с архивом Clarke [zip] на CrossWire и записью [locked]
  // в `crosswire.lock.json` (нет — модуля в списке нет).
  Future<CatalogRun> run({
    List<int>? zip,
    CrossWireSource? locked,
    CatalogRun? after,
    DateTime? now,
    List<EbibleTranslation> translations = const [],
    int? limit,
    Set<String> rebuild = const {},
    String? rebuildBefore,
  }) {
    if (zip != null) {
      fetcher.other[clarkeUrl] = zip;
    }

    return runCatalogBuild(
      pause: (_) async {},
      translations: translations,
      previous: after?.index ?? CatalogIndex.empty(),
      lock: after?.lock ?? const SourcesLock({}),
      pending: after?.deletions ?? const [],
      crosswire: {'Clarke': ?locked},
      overrides: const Overrides(),
      fetcher: fetcher,
      publisher: publisher,
      work: work,
      now: now ?? DateTime.utc(2026, 11),
      limit: limit,
      rebuild: rebuild,
      rebuildBefore: rebuildBefore,
      clock: () => DateTime.utc(2026, 11),
    );
  }

  IndexModule entry(CatalogRun result) =>
      result.index.modules.singleWhere((m) => m.id == id);

  test('a CrossWire module enters the index as commentaries', () async {
    final zip = _clarke();

    final result = await run(zip: zip, locked: _locked(zip));

    final module = entry(result);
    final bytes = publisher.releases['build-2026-11-01']!['$id-2021-10-19.hb']!;
    expect(module.type, 'commentaries');
    expect(module.abbreviation, 'Clarke');
    expect(module.name, 'Clarke Commentary');
    expect(module.description, 'First paragraph.');
    expect(module.language, 'en');
    expect(module.languageName, 'English');
    expect(module.languageNameEnglish, 'English');
    expect(module.script, 'Latn');
    expect(module.direction, WritingDirection.ltr);
    expect(module.license, 'PD');
    expect(module.copyright, 'Public Domain');
    expect(module.books, (ot: 1, nt: 1, dc: 0));
    expect(module.size, bytes.length);
    expect(module.sha256, sha256.convert(bytes).toString());
    expect(module.url, '$_release/build-2026-11-01/$id-2021-10-19.hb');
    expect(module.version, '2021-10-19');
    expect(module.moduleFormat, formatVersion);

    expect(publisher.files('sources-2026-11-01'), ['$id-2021-10-19.zip']);
    expect(publisher.prerelease, {'sources-2026-11-01'});
    expect(
      result.lock.entries[id],
      LockedSource(
        id: id,
        updateDate: '2021-10-19',
        sha256: sha256.convert(zip).toString(),
        release: 'sources-2026-11-01',
        asset: '$id-2021-10-19.zip',
        fetched: '2026-11-01',
      ),
    );
    expect(fetcher.calls, [clarkeUrl]);
    expect(result.report.built, [id]);
    expect(
      result.report.commentaries[id],
      'comments 2, book articles 0, chapter articles 0, links 0, '
      'unresolved 0',
    );

    final file = File(p.join(work.path, 'module.hb'))..writeAsBytesSync(bytes);
    final m = CommentaryModule.open(file.path);
    addTearDown(m.close);
    expect(m.meta.catalog, 'hisbible');
    expect(m.meta.catalogId, id);
    expect(m.meta.version, '2021-10-19');
  });

  test('the limit does not hold back CrossWire modules', () async {
    final zip = _clarke();
    fetcher.ebible[Uri.parse('https://ebible.org/Scriptures/aaa_usfm.zip')] =
        const [];

    final result = await run(
      zip: zip,
      locked: _locked(zip),
      limit: 0,
      translations: [_translation('aaa')],
    );

    expect(result.report.built, [id]);
    expect(result.report.waiting, ['aaa']);
  });

  test('the same archive: unchanged, but checked against the lock', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));
    publisher.uploads.clear();
    fetcher.calls.clear();

    final second = await run(
      zip: zip,
      locked: _locked(zip),
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(second.report.unchanged, [id]);
    expect(second.report.built, isEmpty);
    expect(entry(second), entry(first));
    expect(second.lock, first.lock);
    expect(publisher.uploads, isEmpty);
    expect(fetcher.calls, [clarkeUrl]);
    expect(second.index.updated, first.index.updated);
  });

  test('an archive that differs from the lock fails and stays', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));

    final second = await run(
      zip: _clarke(extra: ' Changed.'),
      locked: _locked(zip),
      after: first,
      now: DateTime.utc(2026, 12),
    );

    expect(entry(second), entry(first));
    expect(second.index.withdrawn, isEmpty);
    expect(second.lock, first.lock);
    expect(
      second.report.failed[id]!.single,
      allOf(
        contains('the CrossWire archive of Clarke changed'),
        contains('--crosswire Clarke <out.hb> --accept-new-source'),
      ),
    );
    expect(second.deletions, isEmpty);
  });

  test(
    'a new module whose archive differs from the lock is left out',
    () async {
      final result = await run(
        zip: _clarke(extra: ' Changed.'),
        locked: _locked(_clarke()),
      );

      expect(result.index.modules, isEmpty);
      expect(result.lock.entries, isEmpty);
      expect(result.report.failed.keys, [id]);
      expect(publisher.uploads, isEmpty);
    },
  );

  test('a failed fetch keeps the module', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));
    fetcher.errors[clarkeUrl] = StateError('offline');

    final second = await run(locked: _locked(zip), after: first);

    expect(entry(second), entry(first));
    expect(second.report.failed[id]!.single, contains('offline'));
  });

  test('an accepted archive of the same date is the next revision', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));
    final changed = _clarke(extra: ' Changed.');

    final second = await run(
      zip: changed,
      locked: _locked(changed),
      after: first,
      now: DateTime.utc(2026, 12),
    );

    final module = entry(second);
    expect(module.version, '2021-10-19.1');
    expect(module.url, '$_release/build-2026-12-01/$id-2021-10-19.1.hb');
    expect(second.lock.entries[id]!.sha256, _locked(changed).sha256);
    expect(second.lock.entries[id]!.release, 'sources-2026-12-01');
    expect(
      second.deletions,
      containsAll([
        (release: 'build-2026-11-01', asset: '$id-2021-10-19.hb'),
        (release: 'sources-2026-11-01', asset: '$id-2021-10-19.zip'),
      ]),
    );
  });

  test('a new SwordVersionDate starts from the bare date', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));
    final next = _clarke(version: '2027-01-02');

    final second = await run(
      zip: next,
      locked: _locked(next, version: '2027-01-02'),
      after: first,
      now: DateTime.utc(2027, 2),
    );

    expect(entry(second).version, '2027-01-02');
    expect(second.lock.entries[id]!.updateDate, '2027-01-02');
  });

  test('--rebuild and --rebuild-before give the next revision', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));

    final rebuilt = await run(
      zip: zip,
      locked: _locked(zip),
      after: first,
      rebuild: {id},
      now: DateTime.utc(2026, 12),
    );
    expect(entry(rebuilt).version, '2021-10-19.1');
    expect(rebuilt.report.failed, isEmpty);
    expect(rebuilt.report.rebuildMissed, isEmpty);
    // Копия исходника та же: заново не выкладывается.
    expect(rebuilt.lock, first.lock);
    expect(publisher.files('sources-2026-12-01'), isEmpty);

    final aged = await run(
      zip: zip,
      locked: _locked(zip),
      after: rebuilt,
      rebuildBefore: '2026-12-15',
      now: DateTime.utc(2026, 12, 20),
    );
    expect(entry(aged).version, '2021-10-19.2');

    final again = await run(
      zip: zip,
      locked: _locked(zip),
      after: aged,
      rebuildBefore: '2026-12-15',
      now: DateTime.utc(2026, 12, 21),
    );
    expect(again.report.unchanged, [id]);
  });

  test('a module taken out of the lock is withdrawn', () async {
    final zip = _clarke();
    final first = await run(zip: zip, locked: _locked(zip));

    final second = await run(after: first, now: DateTime.utc(2026, 12));

    expect(second.index.modules, isEmpty);
    expect(second.index.withdrawn.single.id, id);
    expect(second.lock.entries, isEmpty);
    expect(second.report.withdrawn, [id]);
    expect(
      second.deletions,
      containsAll([
        (release: 'build-2026-11-01', asset: '$id-2021-10-19.hb'),
        (release: 'sources-2026-11-01', asset: '$id-2021-10-19.zip'),
      ]),
    );
  });

  test('a failed module upload leaves no source copy behind', () async {
    final zip = _clarke();
    publisher.broken = (asset) => asset.endsWith('.hb');

    final result = await run(zip: zip, locked: _locked(zip));

    expect(result.index.modules, isEmpty);
    expect(result.lock.entries, isEmpty);
    expect(result.report.failed.keys, [id]);
    expect(result.deletions, [
      (release: 'sources-2026-11-01', asset: '$id-2021-10-19.zip'),
    ]);
  });

  test('the report lists the commentaries built', () async {
    final zip = _clarke();

    final result = await run(zip: zip, locked: _locked(zip));

    expect(
      result.report.toMarkdown(),
      contains(
        '## Commentaries\n\n- `$id`: comments 2, book articles 0, '
        'chapter articles 0, links 0, unresolved 0\n',
      ),
    );
  });
}

EbibleTranslation _translation(String id) => EbibleTranslation(
  languageCode: 'eng',
  translationId: id,
  languageName: 'English',
  languageNameInEnglish: 'English',
  title: 'Bible $id',
  description: 'About $id',
  redistributable: true,
  copyright: '© $id',
  updateDate: '2026-09-01',
  publicationUrl: 'https://ebible.org/$id/',
  otVerses: 1,
  ntVerses: 0,
  dcVerses: 0,
  textDirection: WritingDirection.ltr,
  downloadable: true,
  shortTitle: id,
  script: 'Latin',
);
