import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('a version is a date with an optional revision', () {
    expect(moduleVersionDate('2025-03-04'), '2025-03-04');
    expect(moduleVersionDate('2025-03-04.1'), '2025-03-04');
    expect(moduleVersionDate('2025-03-04.12'), '2025-03-04');
    expect(moduleVersionDate('2024-02-29'), '2024-02-29');
  });

  test('anything else is not a version', () {
    for (final version in [
      '',
      '2025-3-4',
      '20250304',
      '2025-03-04.',
      '2025-03-04.0',
      '2025-03-04.01',
      '2025-03-04.-1',
      '2025-03-04.1.2',
      '2025-03-04.a',
      '2025-03-04 ',
      ' 2025-03-04',
      '2025-03-04-1',
      '2025-13-01',
      '2025-00-01',
      '2025-02-29',
      '2025-04-31',
      '2025-03-00',
      '٢٠٢٥-٠٣-٠٤',
    ]) {
      expect(moduleVersionDate(version), isNull, reason: '"$version"');
    }
  });
}
