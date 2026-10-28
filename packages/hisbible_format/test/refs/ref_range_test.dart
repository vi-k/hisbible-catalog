import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('RefRange parses one verse and a range', () {
    expect(RefRange.parse('MAT.1.1'), const RefRange(VerseRef(470, 1, 1)));
    expect(
      RefRange.parse('GEN.1.1-GEN.2.3'),
      const RefRange(VerseRef(10, 1, 1), VerseRef(10, 2, 3)),
    );
    expect(RefRange.parse('GEN.1.1-GEN.2.3')!.encode(), 'GEN.1.1-GEN.2.3');
  });

  test('RefRange rejects what it cannot read', () {
    for (final bad in [
      '',
      'MAT',
      'MAT.1',
      'XXX.1.1',
      'MAT.0.1',
      'MAT.1.x',
      'MAT.1.1-',
      'MAT.2.1-MAT.1.1',
    ]) {
      expect(RefRange.parse(bad), isNull, reason: bad);
    }
  });
}
