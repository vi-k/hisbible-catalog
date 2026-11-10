import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('options: values, the flag, unknown and repeated keys', () {
    Map<String, String>? options(List<String> args) =>
        parseCliOptions(args)?.options;

    expect(options(['--csv', 'a.csv', '--dry-run', '--limit', '5']), {
      '--csv': 'a.csv',
      '--dry-run': '',
      '--limit': '5',
    });
    expect(options(['--limit', '']), {'--limit': ''});
    expect(options(['--deadline', '300', '--allow-mass-withdrawal']), {
      '--deadline': '300',
      '--allow-mass-withdrawal': '',
    });
    expect(options(['--bogus', 'x']), isNull);
    expect(options(['--csv', 'a', '--csv', 'b']), isNull);
    expect(options(['--dry-run', '--dry-run']), isNull);
    expect(options(['--csv']), isNull, reason: 'no value');
  });

  test('--edition takes a folder and an output path', () {
    expect(
      parseCliOptions(['--edition', 'editions/russyn', 'out.hb'])?.options,
      {'--edition': 'editions/russyn', editionOutKey: 'out.hb'},
    );
    expect(parseCliOptions(['--edition', 'editions/russyn']), isNull);
  });

  test('--rebuild repeats and takes only translation ids', () {
    final parsed = parseCliOptions([
      '--rebuild',
      'engkjv',
      '--dry-run',
      '--rebuild',
      'ru_syn-2',
    ]);
    expect(parsed?.rebuild, ['engkjv', 'ru_syn-2']);
    expect(parsed?.options, {'--dry-run': ''});
    expect(parseCliOptions(['--csv', 'a'])?.rebuild, isEmpty);
    expect(parseCliOptions(['--rebuild']), isNull, reason: 'no value');
    expect(parseCliOptions(['--rebuild', '']), isNull);
    expect(parseCliOptions(['--rebuild', 'a/../b']), isNull);
    expect(parseCliOptions(['--rebuild', 'a b']), isNull);
  });

  test('--rebuild-before takes a real date', () {
    expect(parseCliOptions(['--rebuild-before', '2026-10-29'])?.options, {
      '--rebuild-before': '2026-10-29',
    });
    for (final bad in ['', 'x', '2026-10', '2026-02-30', '29.10.2026']) {
      expect(parseCliOptions(['--rebuild-before', bad]), isNull, reason: bad);
    }
    expect(parseCliOptions(['--rebuild-before']), isNull, reason: 'no value');
    expect(
      parseCliOptions([
        '--rebuild-before',
        '2026-10-29',
        '--rebuild-before',
        '2026-10-30',
      ]),
      isNull,
    );
  });

  test('a refused withdrawal or a missed rebuild makes the run red', () {
    expect(catalogExitCode(const BuildReport(date: '2026-12-01')), 0);
    expect(
      catalogExitCode(
        const BuildReport(
          date: '2026-12-01',
          withdrawalRefused: 'Withdrawal refused: 25 modules',
        ),
      ),
      redRunExitCode,
    );
    expect(
      catalogExitCode(
        const BuildReport(date: '2026-12-01', rebuildMissed: ['aaa']),
      ),
      redRunExitCode,
    );
    expect(
      catalogExitCode(
        const BuildReport(date: '2026-12-01', editionsFailed: ['russyn']),
      ),
      redRunExitCode,
    );
    expect(redRunExitCode, isNot(anyOf(0, 1, 64)));
  });

  test('a failed edition is a bold reason in the report', () {
    const report = BuildReport(
      date: '2026-12-01',
      editionsFailed: ['abc', 'russyn'],
    );

    expect(report.editionProblem, startsWith('Edition not built: abc, russyn'));
    expect(report.toMarkdown(), contains('\n**Edition not built: abc, russyn'));
    expect(const BuildReport(date: '2026-12-01').editionProblem, isNull);
  });

  test('--edition that hits a file system error is not built', () async {
    final dir = Directory.systemTemp.createTempSync('build_cli_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final edition = Directory(p.join(dir.path, 'abc'))..createSync();
    Directory(p.join(edition.path, 'usfm')).createSync();
    File(p.join(edition.path, 'edition.json')).writeAsStringSync(
      jsonEncode({
        for (final key in [
          'abbreviation',
          'name',
          'description',
          'languageName',
          'languageNameEnglish',
          'copyright',
          'sourceUrl',
        ])
          key: key,
        'id': 'abc',
        'language': 'ru',
        'script': 'Cyrl',
        'direction': 'ltr',
        'license': 'PD',
      }),
    );
    // `spelling.tsv` — папка: есть, но не читается.
    Directory(p.join(edition.path, 'spelling.tsv')).createSync();
    final err = StringBuffer();

    final code = await runBuildCli([
      '--edition',
      edition.path,
      p.join(dir.path, 'abc.hb'),
    ], err: err);

    expect(code, 1);
    expect(err.toString(), contains('edition not built'));
  });

  test('a --rebuild-before date after today exits with 64', () async {
    final err = StringBuffer();

    expect(await runBuildCli(['--rebuild-before', '2999-01-01'], err: err), 64);
    expect(err.toString(), allOf(contains('after today'), contains('usage:')));
  });

  test('bad arguments exit with 64 and the usage', () async {
    for (final args in [
      ['--bogus'],
      ['--csv', 'a', '--csv', 'b'],
      ['--limit', 'x'],
      ['--limit', '-1'],
      ['--deadline', 'x'],
      ['--deadline', '0'],
      ['--deadline'],
      ['--allow-mass-withdrawal', 'x'],
      ['--one', 'a.zip'],
      ['--out', 'a.hb'],
      ['--apply-deletions', 'd.json', '--dry-run'],
      ['--rebuild', 'a/b'],
      ['--one', 'a.zip', '--csv', 'a.csv', '--rebuild', 'aaa'],
      ['--apply-deletions', 'd.json', '--rebuild', 'aaa'],
      ['--rebuild-before', 'tomorrow'],
      ['--one', 'a.zip', '--csv', 'a.csv', '--rebuild-before', '2026-10-29'],
      ['--apply-deletions', 'd.json', '--rebuild-before', '2026-10-29'],
      ['--accept-new-source'],
      ['--openbible', 'o.hb', '--dry-run'],
      ['--openbible', 'o.hb', '--rebuild', 'aaa'],
    ]) {
      final err = StringBuffer();

      expect(await runBuildCli(args, err: err), 64, reason: '$args');
      expect(err.toString(), contains('usage:'), reason: '$args');
    }
  });

  test('--apply-deletions with a missing file fails with a message', () async {
    final dir = Directory.systemTemp.createTempSync('build_cli_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final missing = p.join(dir.path, 'deletions.json');
    final err = StringBuffer();

    final code = await runBuildCli(['--apply-deletions', missing], err: err);

    expect(code, isNot(0));
    expect(err.toString(), allOf(contains('cannot read'), contains(missing)));
  });

  test('the CSV comes from an http(s) address or a file', () {
    expect(
      csvAddress('https://ebible.org/Scriptures/translations.csv'),
      Uri.parse('https://ebible.org/Scriptures/translations.csv'),
    );
    expect(csvAddress('http://example.org/t.csv'), isNotNull);
    expect(csvAddress('HTTPS://example.org/t.csv'), isNotNull);
    expect(csvAddress('/tmp/translations.csv'), isNull);
    expect(csvAddress('data/translations.csv'), isNull);
    expect(csvAddress('ftp://example.org/t.csv'), isNull);
    expect(csvAddress(r'C:\data\translations.csv'), isNull);
  });
}
