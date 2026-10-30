import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

import 'zcom_fixture.dart';

void main() {
  test('kjvCanon: 66 books, 31102 verses, all in osisBooks', () {
    expect(kjvCanon, hasLength(66));
    expect(kjvCanon.first.osis, 'Gen');
    expect(kjvCanon[kjvOldTestamentBooks].osis, 'Matt');
    expect(kjvCanon.last.osis, 'Rev');
    expect(
      kjvCanon.fold(0, (sum, b) => sum + b.verses.fold(0, (s, v) => s + v)),
      31102,
    );
    expect(kjvCanon.map((b) => b.osis).toSet(), osisBooks.keys.toSet());
    // Места заветов, как в настоящих модулях: 24115 и 8246 с заголовком.
    expect(testamentPlaces('ot') + 2, 24115);
    expect(testamentPlaces('nt') + 2, 8246);
  });

  for (final size in [10, 12]) {
    test('reads records of zCom with $size-byte index entries', () {
      final fixture = ZComFixture()
        ..put('Gen', 0, 0, 'book')
        ..put('Gen', 1, 0, 'chapter')
        ..put('Gen', 1, 1, 'Gen 1:1')
        ..put('Gen', 1, 3, 'Gen 1:3-5', verseEnd: 5)
        ..put('Mal', 4, 6, 'last of OT')
        ..put('Matt', 1, 1, 'Matt 1:1')
        ..put('Rev', 22, 21, 'last');

      final records = readZCom(
        fixture.files(entrySize: size),
        indexEntrySize: size,
      );

      expect(
        records.map((r) => (r.book, r.chapter, r.verse, r.verseEnd, r.text)),
        [
          (10, 0, 0, null, 'book'),
          (10, 1, 0, null, 'chapter'),
          (10, 1, 1, null, 'Gen 1:1'),
          (10, 1, 3, 5, 'Gen 1:3-5'),
          (460, 4, 6, null, 'last of OT'),
          (470, 1, 1, null, 'Matt 1:1'),
          (730, 22, 21, null, 'last'),
        ],
      );
      expect(records.every((r) => r.chapterEnd == null), isTrue);
    });
  }

  test('a long record needs four length bytes', () {
    final long = 'x' * 70000;
    final fixture = ZComFixture()..put('Gen', 1, 1, long);

    final records = readZCom(fixture.files(entrySize: 12), indexEntrySize: 12);

    expect(records.single.text, long);
  });

  test('same record on places of two chapters: one range', () {
    final files = (ZComFixture()..put('Gen', 1, 31, 'a')).files();
    // Тот же ключ на Быт 2:1 и на записи главы 2 между ними.
    final index = ByteData.sublistView(Uint8List.fromList(files['ot.bzv']!));
    final (_, from) = placeIndex('Gen', 1, 31);
    for (final place in [
      placeIndex('Gen', 2, 0).$2,
      placeIndex('Gen', 2, 1).$2,
    ]) {
      for (var i = 0; i < 10; i++) {
        index.setUint8(
          (place + 2) * 10 + i,
          index.getUint8((from + 2) * 10 + i),
        );
      }
    }
    files['ot.bzv'] = index.buffer.asUint8List();

    final record = readZCom(files, indexEntrySize: 10).single;

    expect(
      (record.chapter, record.verse, record.chapterEnd, record.verseEnd),
      (1, 31, 2, 1),
    );
  });

  test('a range does not run into the next book', () {
    final fixture = ZComFixture()..put('Gen', 50, 26, 'end of Gen');
    final files = fixture.files();
    final index = ByteData.sublistView(Uint8List.fromList(files['ot.bzv']!));
    final (_, from) = placeIndex('Gen', 50, 26);
    final (_, exodus) = placeIndex('Exod', 0, 0);
    for (var i = 0; i < 10; i++) {
      index.setUint8(
        (exodus + 2) * 10 + i,
        index.getUint8((from + 2) * 10 + i),
      );
    }
    files['ot.bzv'] = index.buffer.asUint8List();

    final records = readZCom(files, indexEntrySize: 10);

    expect(records.map((r) => (r.book, r.chapter, r.verse, r.verseEnd)), [
      (10, 50, 26, null),
      (20, 0, 0, null),
    ]);
  });

  test('missing testament files and other block letters', () {
    final fixture = ZComFixture()..put('Matt', 5, 3, 'blessed');

    final records = readZCom(fixture.files(kind: 'c'), indexEntrySize: 10);

    expect(records.single.book, 470);
    expect(readZCom(const {}, indexEntrySize: 10), isEmpty);
  });

  test('an empty testament with all files reads as empty', () {
    final fixture = ZComFixture()..put('Gen', 1, 1, 'a');

    final records = readZCom(
      fixture.files(allTestaments: true, entrySize: 12),
      indexEntrySize: 12,
    );

    expect(records, hasLength(1));
  });

  test('a short index leaves the rest empty', () {
    final files = (ZComFixture()..put('Gen', 1, 1, 'a')).files();
    files['ot.bzv'] = files['ot.bzv']!.sublist(0, 10 * 10);

    expect(readZCom(files, indexEntrySize: 10).single.text, 'a');
  });

  test('broken files are a FormatException', () {
    final good = (ZComFixture()..put('Gen', 1, 1, 'a')).files();
    for (final (name, broken) in [
      ('index not a multiple', {...good, 'ot.bzv': good['ot.bzv']!.sublist(1)}),
      (
        'index too long',
        {
          ...good,
          'ot.bzv': [...good['ot.bzv']!, ...List.filled(10, 0)],
        },
      ),
      ('no block file', {...good}..remove('ot.bzz')),
      ('block cut off', {...good, 'ot.bzz': good['ot.bzz']!.sublist(0, 4)}),
      ('no block', {...good, 'ot.bzs': <int>[]}),
    ]) {
      expect(
        () => readZCom(broken, indexEntrySize: 10),
        throwsFormatException,
        reason: name,
      );
    }
    expect(() => readZCom(good, indexEntrySize: 11), throwsArgumentError);
  });

  test('a record that is not UTF-8 is a FormatException', () {
    final files = (ZComFixture()..put('Gen', 1, 1, 'ab')).files();
    // Тот же блок и те же два байта, но не UTF-8.
    final packed = ZLibEncoder().convert(const [0xFF, 0xFE]);
    files
      ..['ot.bzz'] = packed
      ..['ot.bzs'] =
          (ByteData(12)
                ..setUint32(0, 0, Endian.little)
                ..setUint32(4, packed.length, Endian.little)
                ..setUint32(8, 2, Endian.little))
              .buffer
              .asUint8List();

    expect(() => readZCom(files, indexEntrySize: 10), throwsFormatException);
  });

  test('book numbers are from the catalog', () {
    for (final book in kjvCanon) {
      expect(BookCatalog.byNumber(osisBooks[book.osis]!), isNotNull);
    }
  });
}
