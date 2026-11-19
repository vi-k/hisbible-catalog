import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('VerseRef with a part', () {
    expect(const VerseRef(1, 2, 6, 'b'), isNot(const VerseRef(1, 2, 6)));
    expect(const VerseRef(1, 2, 6, 'b'), const VerseRef(1, 2, 6, 'b'));
    expect(
      const VerseRef(1, 2, 6, 'b').hashCode,
      const VerseRef(1, 2, 6, 'b').hashCode,
    );
    expect(const VerseRef(1, 2, 6, 'b').whole, const VerseRef(1, 2, 6));
    expect(const VerseRef(1, 2, 6).whole, const VerseRef(1, 2, 6));
    expect(const VerseRef(1, 2, 6).part, '');
    expect(const VerseRef(1, 2, 6, 'b').toString(), '1:2:6b');
    expect(const VerseRef(1, 2, 6).toString(), '1:2:6');
  });
}
