import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('footnotes without their Bible are equal by abbreviation', () {
    expect(
      const FootnotesWithoutBible('RST+'),
      const FootnotesWithoutBible('RST+'),
    );
    expect(
      const FootnotesWithoutBible('RST+').hashCode,
      const FootnotesWithoutBible('RST+').hashCode,
    );
    expect(
      const FootnotesWithoutBible('RST+'),
      isNot(const FootnotesWithoutBible('NRT')),
    );
    expect(
      const FootnotesWithoutBible('RST+'),
      isNot(const ConversionFailed('RST+')),
    );
    expect(
      const FootnotesWithoutBible('RST+').toString(),
      'FootnotesWithoutBible(RST+)',
    );
  });
}
