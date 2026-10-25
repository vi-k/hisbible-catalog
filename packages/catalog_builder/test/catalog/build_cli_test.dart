import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('options: values, the flag, unknown and repeated keys', () {
    expect(parseCliOptions(['--csv', 'a.csv', '--dry-run', '--limit', '5']), {
      '--csv': 'a.csv',
      '--dry-run': '',
      '--limit': '5',
    });
    expect(parseCliOptions(['--limit', '']), {'--limit': ''});
    expect(parseCliOptions(['--bogus', 'x']), isNull);
    expect(parseCliOptions(['--csv', 'a', '--csv', 'b']), isNull);
    expect(parseCliOptions(['--dry-run', '--dry-run']), isNull);
    expect(parseCliOptions(['--csv']), isNull, reason: 'no value');
  });

  test('bad arguments exit with 64 and the usage', () async {
    for (final args in [
      ['--bogus'],
      ['--csv', 'a', '--csv', 'b'],
      ['--limit', 'x'],
      ['--limit', '-1'],
      ['--one', 'a.zip'],
      ['--out', 'a.hb'],
      ['--apply-deletions', 'd.json', '--dry-run'],
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
