import 'package:catalog_builder/src/edition/spelling.dart';
import 'package:test/test.dart';

void main() {
  final table = SpellingTable({
    'придти': 'прийти',
    'святаго': 'святого',
    'лицем': 'лицом',
  });

  test('replaces whole words only', () {
    final result = applySpelling(r'\v 1 придти пришедши придтись', table);
    expect(result.text, r'\v 1 прийти пришедши придтись');
  });

  test('keeps capital and all caps', () {
    expect(applySpelling('Святаго', table).text, 'Святого');
    expect(applySpelling('СВЯТАГО', table).text, 'СВЯТОГО');
  });

  test('keeps the stress mark', () {
    expect(applySpelling('ли́цем', table).text, 'ли́цом');
  });

  test('skips markers and attributes', () {
    expect(applySpelling(r'\add лицем\add*', table).text, r'\add лицом\add*');
    const linked = r'\xt Ин 1:3|link-href="JHN 1:3"\xt*';
    expect(applySpelling(linked, table).text, linked);
  });

  test('counts replacements', () {
    final result = applySpelling('лицем и лицем, Святаго', table);
    expect(result.replaced, 3);
  });

  test('parses a table, skipping blanks and comments', () {
    final parsed = parseSpellingTable('# заголовок\n\nлицем\tлицом\n');
    expect(parsed.words, {'лицем': 'лицом'});
  });

  test('bad line is a FormatException', () {
    expect(
      () => parseSpellingTable('# c\nлицем лицом\n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('2'),
        ),
      ),
    );
  });
}
