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
    expect(BookCatalog.codeOf(305), 'H305');
    // Дополнения к Есфири пишутся кодом USFM, а старый код модулей,
    // записанных раньше, читается и дальше.
    expect(BookCatalog.codeOf(192), 'ESG');
    expect(BookCatalog.numberOfCode('ESG'), 192);
    expect(BookCatalog.numberOfCode('H192'), 192);
    expect(BookCatalog.numberOfCode('H999'), 999);
    expect(BookCatalog.numberOfCode('XYZ'), isNull);
  });

  test('numeric codes of books with a SIL code or out of range are null', () {
    // У Бытия (10) есть код SIL, и `H10` его не заменяет.
    expect(BookCatalog.numberOfCode('H10'), isNull);
    expect(BookCatalog.numberOfCode('H0'), isNull);
    expect(BookCatalog.numberOfCode('H010'), isNull);
    expect(BookCatalog.numberOfCode('H99999999999999999999'), isNull);
    expect(BookCatalog.numberOfCode('H9223372036854775808'), isNull);
    expect(moduleFileName("NRT'23", ModuleType.bible), "NRT'23.hb");
  });
}
