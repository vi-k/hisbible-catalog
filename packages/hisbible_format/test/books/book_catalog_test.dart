import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('catalog has 85 books and maps legacy numbers', () {
    expect(BookCatalog.all, hasLength(85));
    expect(BookCatalog.normalize(790), 145);
    expect(BookCatalog.normalize(750), 468);
    expect(BookCatalog.normalize(500), 500);
    expect(BookCatalog.byNumber(200)!.number, 462);
    expect(BookCatalog.byNumber(810), isNull);
    expect(BookCatalog.bySilCode('2ES')!.number, 468);
    expect(BookCatalog.bySilCode('1ES')!.number, 165);
    expect(BookCatalog.byNumber(230)!.color, 0x66ff99);
  });

  test('catalog numbers and SIL codes are unique', () {
    final numbers = BookCatalog.all.map((b) => b.number).toSet();
    expect(numbers, hasLength(85));
    final codes = BookCatalog.all.map((b) => b.silCode).nonNulls.toList();
    expect(codes.toSet(), hasLength(codes.length));
    expect(
      BookCatalog.all.where((b) => b.silCode == null).map((b) => b.number),
      [192, 305],
    );
  });

  test('testament splits at the end of prophets', () {
    expect(BookCatalog.byNumber(460)!.testament, Testament.old);
    expect(BookCatalog.byNumber(468)!.testament, Testament.old);
    expect(BookCatalog.byNumber(470)!.testament, Testament.newTestament);
    expect(BookCatalog.byNumber(780)!.testament, Testament.newTestament);
  });

  test('russian order puts deuterocanon in their places', () {
    const o = BookCatalog.russianOrder;
    expect(o, hasLength(78));
    expect(o.toSet(), hasLength(78));
    expect(o.every((b) => BookCatalog.byNumber(b) != null), isTrue);
    int at(int b) => o.indexOf(b);
    expect(at(145), at(140) + 1);
    expect(
      [at(165), at(170), at(180)],
      [at(160) + 1, at(160) + 2, at(160) + 3],
    );
    expect([at(270), at(280)], [at(260) + 1, at(260) + 2]);
    expect([at(315), at(320)], [at(310) + 1, at(310) + 2]);
    expect(o.sublist(at(460) + 1, at(470)), [462, 464, 466, 468]);
    expect(at(660), at(510) + 1);
    expect(o.last, 730);
  });
}
