import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('codes round trip', () {
    for (final book in BookCatalog.all) {
      expect(
        BookCatalog.numberOfCode(BookCatalog.codeOf(book.number)),
        book.number,
      );
    }
    expect(BookCatalog.codeOf(10), 'GEN');
    expect(BookCatalog.codeOf(192), 'H192');
    expect(BookCatalog.numberOfCode('H999'), 999);
    expect(BookCatalog.numberOfCode('XYZ'), isNull);
    expect(moduleFileName("NRT'23", ModuleType.bible), "NRT'23.hb");
  });
}
