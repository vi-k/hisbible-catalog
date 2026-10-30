// Разметка OSIS и HTML режется на строки по тегам, без пробелов на стыках.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:catalog_builder/catalog_builder.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'zcom_fixture.dart';

Map<String, List<int>> _clarkeFiles() =>
    (ZComFixture()
          ..put('Gen', 0, 0, '<div type="book" sID="g"/> ')
          ..put('Gen', 1, 0, '<chapter n="1" osisID="Gen.1" sID="Gen.1"/> ')
          ..put(
            'Gen',
            1,
            1,
            '<title type="x-s">Preface</title> <div sID="a" type="x-p"/>Moses. '
                '<hi type="bold">Verse 1</hi> In the beginning, see '
                '<reference osisRef="Exo.20.11">Exo 20:11</reference>.',
          )
          ..put('Gen', 1, 2, '<hi type="bold">Verse 2</hi> Void.')
          ..put('Gen', 1, 3, '<hi type="bold">Verse 3</hi> Light.', verseEnd: 4)
          ..put('Gen', 2, 1, '<title type="x-s">Introduction</title> Sabbath.')
          ..put('Matt', 1, 1, '<hi type="bold">Verse 1</hi> The book.'))
        .files();

void main() {
  late Directory dir;
  late String path;
  final now = DateTime.utc(2026, 10, 30);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crosswire_test');
    path = p.join(dir.path, 'clarke.hb');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('builds a commentaries module from a zCom archive', () {
    final out = buildCrossWire(
      crosswireZip('Clarke', _clarkeFiles()),
      'Clarke',
      path,
      now: now,
    );

    expect(out.version, '2021-10-19');
    expect(out.records, 7);
    expect(out.comments, 4);
    expect(out.bookArticles, 1);
    expect(out.chapterArticles, 1);
    expect((out.split, out.whole, out.shifted), (1, 1, 0));
    expect(out.empty, 2); // записи книги и главы — одни вехи
    expect(out.links, 1);
    final m = CommentaryModule.open(path);
    addTearDown(m.close);
    expect(m.comments(10, 0).single.html, '<h4>Preface</h4><p>Moses.</p>');
    expect(m.comments(10, 1).map((c) => (c.verse, c.verseEnd, c.html)), [
      (
        1,
        null,
        '<p><b>Verse 1</b> In the beginning, see '
            '<a href="ref:EXO.20.11">Exo 20:11</a>.</p>',
      ),
      (2, null, '<p><b>Verse 2</b> Void.</p>'),
      (3, 4, '<p><b>Verse 3</b> Light.</p>'),
    ]);
    expect(
      m.comments(10, 2).single.html,
      '<h4>Introduction</h4><p>Sabbath.</p>',
    );
    expect(m.comments(10, 2).single.verse, 0);
    expect(m.comments(470, 1).single.verse, 1);
    final meta = m.meta;
    expect(meta.type, ModuleType.commentaries);
    expect(meta.abbreviation, 'Clarke');
    expect(meta.name, 'Clarke Commentary');
    expect(meta.language, 'en');
    expect(meta.direction, WritingDirection.ltr);
    expect(meta.script, 'Latn');
    expect(meta.license, 'PD');
    expect(meta.copyright, 'Public Domain');
    expect(meta.description, 'First paragraph.');
    expect(meta.source, 'crosswire:Clarke');
    expect(meta.sourceUrl, 'https://example.org/clarke');
    expect(meta.version, '2021-10-19');
    expect(meta.created, '2026-10-30');
    expect(meta.numbering, 'eng');
    expect(File('$path.part').existsSync(), isFalse);
  });

  test('zCom4 of KD', () {
    final files =
        (ZComFixture()
              ..put(
                'Gen',
                1,
                1,
                '<title type="x-ms">INTRODUCTION</title> Intro. '
                    '<div sID="a" type="x-p"/> '
                    '<reference osisRef="Gen.1.1">Gen 1:1</reference> '
                    '<div eID="a" type="x-p"/> In the beginning'
                    '<note placement="foot">A note.</note>.',
              )
              ..put(
                'Gen',
                1,
                2,
                '<reference osisRef="Gen.1.2-Gen.1.5">Gen 1:2-5</reference> Day',
                verseEnd: 5,
              ))
            .files(entrySize: 12);

    final out = buildCrossWire(
      crosswireZip('KD', files, modDrv: 'zCom4'),
      'KD',
      path,
      now: now,
    );

    expect(
      (out.comments, out.bookArticles, out.split, out.notes),
      (2, 1, 1, 1),
    );
    final m = CommentaryModule.open(path);
    addTearDown(m.close);
    expect(m.comments(10, 1).map((c) => (c.verse, c.verseEnd)), [
      (1, null),
      (2, 5),
    ]);
    expect(
      m.comments(10, 1).first.html,
      '<p><a href="ref:GEN.1.1">Gen 1:1</a></p><p>In the beginning'
      '<sup>1</sup>.</p><p><sup>1</sup> A note.</p>',
    );
  });

  test('a module that is not as expected is refused, nothing written', () {
    for (final (name, zip) in [
      (
        'license',
        crosswireZip('Clarke', _clarkeFiles(), license: 'Copyrighted'),
      ),
      ('driver', crosswireZip('Clarke', _clarkeFiles(), modDrv: 'RawCom')),
      (
        'version',
        crosswireZip('Clarke', _clarkeFiles(), version: '2021-02-30'),
      ),
      ('other module', crosswireZip('KD', _clarkeFiles())),
    ]) {
      expect(
        () => buildCrossWire(zip, 'Clarke', path, now: now),
        throwsFormatException,
        reason: name,
      );
      expect(File(path).existsSync(), isFalse, reason: name);
      expect(File('$path.part').existsSync(), isFalse, reason: name);
    }
    expect(
      () => buildCrossWire(
        crosswireZip('Barnes', _clarkeFiles()),
        'Barnes',
        path,
        now: now,
      ),
      throwsArgumentError,
    );
  });

  test('parseSwordConf: section, first value, continued lines', () {
    final conf = parseSwordConf(
      '﻿# comment\n[KD]\nDescription=Keil\nGlobalOptionFilter=A\n'
      'GlobalOptionFilter=B\nAbout=one \\\ntwo\nbad line\n',
    );
    expect(conf.section, 'KD');
    expect(conf.values['Description'], 'Keil');
    expect(conf.values['GlobalOptionFilter'], 'A');
    expect(conf.values['About'], 'one \ntwo');
    expect(() => parseSwordConf('Description=x\n'), throwsFormatException);
  });

  group('runCrossWire', () {
    late String lockPath;
    final zip = crosswireZip('Clarke', _clarkeFiles());
    final sha = crypto.sha256.convert(zip).toString();

    setUp(() => lockPath = p.join(dir.path, 'crosswire.lock.json'));

    Future<int> run(
      List<int> bytes, {
      String module = 'Clarke',
      bool accept = false,
      StringBuffer? out,
      StringBuffer? err,
      DateTime? at,
    }) => runCrossWire(
      module,
      path,
      fetcher: _FakeFetcher(bytes),
      acceptNewSource: accept,
      lockPath: lockPath,
      now: at ?? now,
      out: out ?? StringBuffer(),
      err: err ?? StringBuffer(),
    );

    test('the first run writes the lock and the module', () async {
      final out = StringBuffer();

      expect(await run(zip, out: out), 0);

      expect(jsonDecode(File(lockPath).readAsStringSync()), {
        'Clarke': {
          'url': '${crosswireUrlBase}Clarke.zip',
          'sha256': sha,
          'version': '2021-10-19',
          'fetched': '2026-10-30',
        },
      });
      expect(readModuleMeta(path).version, '2021-10-19');
      expect(
        out.toString(),
        allOf(
          contains('comments 4, book articles 1, chapter articles 1'),
          contains('verse 1 split 1, whole articles 1'),
          contains('widened to the leading reference 0'),
          contains('links 1, unresolved 0'),
        ),
      );
    });

    test('a changed archive is refused without accept-new-source', () async {
      await run(zip);
      final lockBefore = File(lockPath).readAsStringSync();
      final moduleBefore = File(path).readAsBytesSync();
      final changed = crosswireZip(
        'Clarke',
        _clarkeFiles(),
        version: '2024-01-02',
      );
      final err = StringBuffer();

      expect(await run(changed, err: err), isNonZero);
      expect(err.toString(), contains('--accept-new-source'));
      expect(File(lockPath).readAsStringSync(), lockBefore);
      expect(File(path).readAsBytesSync(), moduleBefore);

      expect(
        await run(changed, accept: true, at: DateTime.utc(2026, 11, 2)),
        0,
      );
      final lock =
          jsonDecode(File(lockPath).readAsStringSync()) as Map<String, Object?>;
      expect(lock['Clarke'], {
        'url': '${crosswireUrlBase}Clarke.zip',
        'sha256': crypto.sha256.convert(changed).toString(),
        'version': '2024-01-02',
        'fetched': '2026-11-02',
      });
      expect(readModuleMeta(path).version, '2024-01-02');
    });

    test('the same archive keeps the fetch date; other entries stay', () async {
      await run(zip);
      final kd = crosswireZip(
        'KD',
        (ZComFixture()..put('Gen', 1, 2, 'Text')).files(entrySize: 12),
        modDrv: 'zCom4',
      );
      expect(await run(kd, module: 'KD'), 0);

      expect(await run(zip, at: DateTime.utc(2027)), 0);

      final lock =
          jsonDecode(File(lockPath).readAsStringSync()) as Map<String, Object?>;
      expect(lock.keys, ['Clarke', 'KD']);
      expect((lock['Clarke']! as Map)['fetched'], '2026-10-30');
      expect(
        (lock['KD']! as Map)['sha256'],
        crypto.sha256.convert(kd).toString(),
      );
    });

    test('an unknown module or a broken archive is an error', () async {
      final err = StringBuffer();

      expect(await run(zip, module: 'Barnes', err: err), isNonZero);
      expect(err.toString(), contains('known: Clarke, KD'));
      final bad = Uint8List.fromList(
        ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('x', [1]))),
      );
      expect(await run(bad), isNonZero);
      expect(File(lockPath).existsSync(), isFalse);
      expect(File(path).existsSync(), isFalse);
    });
  });

  test('--crosswire takes a module and a path', () async {
    expect(
      parseCliOptions(['--crosswire', 'KD', 'kd.hb', '--accept-new-source'])
          ?.options,
      {
        '--crosswire': 'KD',
        crosswireOutKey: 'kd.hb',
        '--accept-new-source': '',
      },
    );
    expect(parseCliOptions(['--crosswire', 'KD']), isNull);
    for (final args in [
      ['--crosswire', 'KD', 'kd.hb', '--dry-run'],
      ['--crosswire', 'KD', 'kd.hb', '--openbible', 'o.hb'],
      ['--crosswire', 'KD', 'kd.hb', '--rebuild', 'aaa'],
      ['--crosswire', 'KD'],
    ]) {
      final err = StringBuffer();

      expect(await runBuildCli(args, err: err), 64, reason: '$args');
      expect(err.toString(), contains('--crosswire <module>'), reason: '$args');
    }
  });
}

final class _FakeFetcher implements HeaderFetcher {
  _FakeFetcher(this.bytes);

  final List<int> bytes;

  @override
  Future<List<int>> get(Uri uri) async => bytes;

  @override
  Future<FetchedFile> getFile(Uri uri) async => FetchedFile(bytes);
}
