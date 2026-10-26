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
    expect(redRunExitCode, isNot(anyOf(0, 1, 64)));
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
