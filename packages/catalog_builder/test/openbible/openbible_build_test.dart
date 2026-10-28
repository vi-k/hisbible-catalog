import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:catalog_builder/catalog_builder.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _tsv =
    'From Verse\tTo Verse\tVotes\t#www.openbible.info CC-BY 2026\n'
    'Gen.1.1\tJohn.1.1-John.1.3\t396\n'
    'Gen.1.1\tPs.33.6\t-2\n'
    'Gen.1.1\tGen.1.1\t5\n'
    'Gen.1.1\tXyz.1.1\t5\n'
    'Gen.50.27\tPs.1.1\t5\n';

void main() {
  late Directory dir;
  late String path;
  final now = DateTime.utc(2026, 1, 3);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('openbible_test');
    path = p.join(dir.path, 'openbible.hb');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('osisBooks: 66 books, all in the catalog', () {
    expect(osisBooks, hasLength(66));
    expect(osisBooks['Matt'], 470);
    expect(osisBooks['John'], 500);
    expect(osisBooks['Gen'], 10);
    expect(osisBooks['Ps'], 230);
    expect(osisBooks['Job'], 220);
    expect(osisBooks['Lam'], 310);
    expect(osisBooks['Esth'], 190);
    expect(osisBooks.values.toSet(), hasLength(66));
    // Ровно книги канона: без второканонических и без книг без кода SIL.
    expect(osisBooks.values.toSet(), {
      for (final book in BookCatalog.all)
        if (!book.deuterocanonical && book.silCode != null) book.number,
    });
  });

  test('builds an eng crossrefs module without negative votes', () {
    final out = buildOpenBible(_tsv, path, version: '2026-01-02', now: now);
    expect(out.written, 1);
    expect(out.negative, 1);
    expect(out.selfLinks, 1);
    expect(out.unknownBook, 1);
    expect(out.outsideEng, 1); // в Быт 50 нет стиха 27
    final m = CrossrefModule.open(path);
    addTearDown(m.close);
    expect(
      m.from(10, 1).single,
      const CrossRef(
        book: 10,
        chapter: 1,
        verse: 1,
        toBook: 500,
        toChapter: 1,
        toVerse: 1,
        toVerseEnd: 3,
        votes: 396,
      ),
    );
    final meta = readModuleMeta(path);
    expect(meta.type, ModuleType.crossReferences);
    expect(meta.abbreviation, 'OpenBible');
    expect(meta.name, 'OpenBible.info');
    expect(meta.language, 'und');
    expect(meta.license, 'CC-BY-4.0');
    expect(meta.copyright, 'OpenBible.info, CC BY');
    expect(meta.numbering, VerseScheme.eng.name);
    expect(meta.version, '2026-01-02');
  });

  test('ranges across chapters; order by verse, then votes descending', () {
    const tsv =
        'From Verse\tTo Verse\tVotes\n'
        '# comment\n'
        'Ps.1.2\tMatt.1.1\t3\n'
        'Gen.1.2\tMatt.5.3-Matt.6.2\t7\n'
        'Gen.1.1\tMatt.1.1\t3\n'
        'Gen.1.1\tMatt.1.2\t9\n'
        'Gen.1.1\tMatt.1.3\t0\n';
    final out = buildOpenBible(tsv, path, version: '2026-01-02', now: now);
    expect(out.written, 5);
    final m = CrossrefModule.open(path);
    addTearDown(m.close);
    final gen = m.from(10, 1);
    expect(gen.map((r) => (r.verse, r.toChapter, r.toVerse, r.votes)), [
      (1, 1, 2, 9),
      (1, 1, 1, 3),
      (1, 1, 3, 0),
      (2, 5, 3, 7),
    ]);
    expect(gen.last.toChapterEnd, 6);
    expect(gen.last.toVerseEnd, 2);
    expect(m.from(230, 1).single.toBook, 470);
  });

  test('a line that is not a link is a FormatException', () {
    expect(
      () => buildOpenBible(
        'From Verse\tTo Verse\tVotes\nGen.1.1\tPs.1.1\n',
        path,
        version: '2026-01-02',
        now: now,
      ),
      throwsFormatException,
    );
  });

  group('runOpenBible', () {
    late String lockPath;
    final zipBytes = _zip(_tsv);
    final okSha = crypto.sha256.convert(zipBytes).toString();
    final date = DateTime.utc(2026, 1, 2, 12);

    setUp(() => lockPath = p.join(dir.path, 'openbible.lock.json'));

    Future<int> run(
      _FakeFetcher fetcher, {
      bool accept = false,
      StringBuffer? err,
    }) => runOpenBible(
      path,
      fetcher: fetcher,
      acceptNewSource: accept,
      lockPath: lockPath,
      now: now,
      out: StringBuffer(),
      err: err ?? StringBuffer(),
    );

    test('the first run writes the lock and the module', () async {
      expect(await run(_FakeFetcher(zipBytes, date)), 0);
      final lock = jsonDecode(File(lockPath).readAsStringSync());
      expect(lock, {
        'url': openBibleUrl,
        'sha256': okSha,
        'lastModified': '2026-01-02',
        'fetched': '2026-01-03',
      });
      expect(readModuleMeta(path).version, '2026-01-02');
    });

    test('a changed source is refused without accept-new-source', () async {
      await run(_FakeFetcher(zipBytes, date));
      final lockBefore = File(lockPath).readAsStringSync();
      final outBefore = File(path).readAsBytesSync();
      final changed = _zip('${_tsv}Gen.1.2\tJohn.1.1\t5\n');
      final err = StringBuffer();

      final code = await run(
        _FakeFetcher(changed, DateTime.utc(2026, 5, 6)),
        err: err,
      );

      expect(code, isNonZero);
      expect(err.toString(), contains('--accept-new-source'));
      expect(File(lockPath).readAsStringSync(), lockBefore);
      expect(File(path).readAsBytesSync(), outBefore);

      expect(
        await run(
          _FakeFetcher(changed, DateTime.utc(2026, 5, 6)),
          accept: true,
        ),
        0,
      );
      final lock =
          jsonDecode(File(lockPath).readAsStringSync()) as Map<String, Object?>;
      expect(lock['sha256'], crypto.sha256.convert(changed).toString());
      expect(lock['lastModified'], '2026-05-06');
      expect(readModuleMeta(path).version, '2026-05-06');
    });

    test('the same source keeps the locked version', () async {
      await run(_FakeFetcher(zipBytes, date));
      final lockBefore = File(lockPath).readAsStringSync();

      expect(await run(_FakeFetcher(zipBytes, DateTime.utc(2027))), 0);

      expect(File(lockPath).readAsStringSync(), lockBefore);
      expect(readModuleMeta(path).version, '2026-01-02');
    });

    test('no Last-Modified on a first run is an error', () async {
      final err = StringBuffer();

      expect(await run(_FakeFetcher(zipBytes, null), err: err), isNonZero);
      expect(err.toString(), contains('Last-Modified'));
      expect(File(lockPath).existsSync(), isFalse);
      expect(File(path).existsSync(), isFalse);
    });

    test('an archive without cross_references.txt is an error', () async {
      final bad = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile.bytes('other.txt', [1])),
        ),
      );

      expect(await run(_FakeFetcher(bad, date)), isNonZero);
      expect(File(lockPath).existsSync(), isFalse);
      expect(File(path).existsSync(), isFalse);
    });
  });

  test('--openbible and --accept-new-source parse', () {
    expect(
      parseCliOptions(['--openbible', 'o.hb', '--accept-new-source'])?.options,
      {'--openbible': 'o.hb', '--accept-new-source': ''},
    );
  });
}

Uint8List _zip(String tsv) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile.bytes('cross_references.txt', utf8.encode(tsv))),
  ),
);

final class _FakeFetcher implements HeaderFetcher {
  _FakeFetcher(this.bytes, this.lastModified);

  final List<int> bytes;
  final DateTime? lastModified;

  @override
  Future<List<int>> get(Uri uri) async => bytes;

  @override
  Future<FetchedFile> getFile(Uri uri) async =>
      FetchedFile(bytes, lastModified: lastModified);
}
