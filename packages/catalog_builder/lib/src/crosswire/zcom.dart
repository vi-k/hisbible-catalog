import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:catalog_builder/src/crosswire/kjv_canon.dart';
import 'package:catalog_builder/src/openbible/osis_books.dart';

/// Запись модуля толкований zCom или zCom4 на одном месте или на нескольких
/// подряд идущих местах.
///
/// Место — по версификации KJV SWORD ([kjvCanon]): [chapter] 0 — запись
/// книги, [verse] 0 — запись главы. Конец — как у толкований формата:
/// без [chapterEnd] он в той же главе, без [verseEnd] запись — на одном
/// месте.
final class ZComRecord {
  /// Создаёт запись.
  const ZComRecord({
    required this.book,
    required this.chapter,
    required this.verse,
    this.chapterEnd,
    this.verseEnd,
    required this.text,
  });

  /// Номер книги справочника.
  final int book;

  /// Глава, с которой начинается место; 0 — запись книги.
  final int chapter;

  /// Стих, с которого начинается место; 0 — запись главы.
  final int verse;

  /// Глава, на которой место кончается; `null` — та же глава.
  final int? chapterEnd;

  /// Последний стих места; `null` — одно место.
  final int? verseEnd;

  /// Текст записи: разметка OSIS как в модуле.
  final String text;

  @override
  String toString() =>
      'ZComRecord($book $chapter:$verse'
      '${chapterEnd == null ? '' : '-$chapterEnd'}'
      '${verseEnd == null ? '' : ':$verseEnd'}, ${text.length} chars)';
}

/// Читает записи модуля толкований zCom (длина записи в указателе — два
/// байта, [indexEntrySize] 10) или zCom4 (четыре байта, 12).
///
/// [files] — файлы каталога данных модуля по именам: `ot.bzs`, `ot.bzv`,
/// `ot.bzz` и то же для `nt` (вместо `b` может стоять другая буква вида
/// блоков). Нет файлов завета — у завета нет записей. Места идут
/// по версификации KJV SWORD: две записи заголовка (модуля и завета),
/// затем у каждой книги запись книги, у каждой главы запись главы и записи
/// стихов. Подряд идущие места с одной и той же записью (тот же блок,
/// смещение и длина) — одна запись на диапазон; места с длиной 0 пусты.
/// Записи заголовка не возвращаются. Указатель короче нужного — недостающие
/// места пусты. Файлы не по форме — [FormatException].
List<ZComRecord> readZCom(
  Map<String, List<int>> files, {
  required int indexEntrySize,
}) {
  if (indexEntrySize != 10 && indexEntrySize != 12) {
    throw ArgumentError.value(indexEntrySize, 'indexEntrySize', 'not 10 or 12');
  }
  final records = <ZComRecord>[];
  for (final (testament, books) in [
    ('ot', kjvCanon.sublist(0, kjvOldTestamentBooks)),
    ('nt', kjvCanon.sublist(kjvOldTestamentBooks)),
  ]) {
    final testamentFiles = _testamentFiles(files, testament);
    if (testamentFiles == null) {
      continue;
    }
    records.addAll(
      _readTestament(testament, testamentFiles, books, indexEntrySize),
    );
  }

  return records;
}

// Файлы завета: указатель мест, указатель блоков и блоки; `null` — нет
// указателя мест.
({List<int> places, List<int> blocks, List<int> data})? _testamentFiles(
  Map<String, List<int>> files,
  String testament,
) {
  final pattern = RegExp('^$testament\\.([a-z])zv\$');
  for (final name in files.keys) {
    final match = pattern.firstMatch(name);
    if (match == null) {
      continue;
    }
    final kind = match[1]!;
    final blocks = files['$testament.${kind}zs'];
    final data = files['$testament.${kind}zz'];
    if (blocks == null || data == null) {
      throw FormatException(
        'zCom: $name without $testament.${kind}zs or $testament.${kind}zz',
      );
    }

    return (places: files[name]!, blocks: blocks, data: data);
  }

  return null;
}

// Место завета: книга, глава, стих; глава 0 — запись книги, стих 0 —
// запись главы.
typedef _Place = ({int book, int chapter, int verse});

List<ZComRecord> _readTestament(
  String testament,
  ({List<int> places, List<int> blocks, List<int> data}) files,
  List<({String osis, List<int> verses})> books,
  int entrySize,
) {
  final places = <_Place>[];
  for (final (:osis, :verses) in books) {
    final book = osisBooks[osis];
    if (book == null) {
      throw StateError('no catalog number for the KJV book $osis');
    }
    places.add((book: book, chapter: 0, verse: 0));
    for (final (i, count) in verses.indexed) {
      for (var verse = 0; verse <= count; verse++) {
        places.add((book: book, chapter: i + 1, verse: verse));
      }
    }
  }

  final index = _bytes(files.places);
  if (index.length % entrySize != 0 ||
      index.length > (places.length + 2) * entrySize) {
    throw FormatException(
      'zCom: $testament index has ${index.length} bytes, expected '
      '${(places.length + 2) * entrySize}',
    );
  }
  final blockIndex = _bytes(files.blocks);
  if (blockIndex.length % 12 != 0) {
    throw FormatException(
      'zCom: $testament block index has ${blockIndex.length} bytes, '
      'not a multiple of 12',
    );
  }
  final data = _bytes(files.data);
  final indexView = ByteData.sublistView(index);
  final blockView = ByteData.sublistView(blockIndex);
  final blockCache = <int, Uint8List>{};

  Uint8List block(int number) => blockCache.putIfAbsent(number, () {
    if ((number + 1) * 12 > blockIndex.length) {
      throw FormatException('zCom: $testament has no block $number');
    }
    final offset = blockView.getUint32(number * 12, Endian.little);
    final size = blockView.getUint32(number * 12 + 4, Endian.little);
    if (offset + size > data.length) {
      throw FormatException('zCom: $testament block $number is cut off');
    }
    final bytes = ZLibDecoder().convert(
      Uint8List.sublistView(data, offset, offset + size),
    );

    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  });

  // Запись места [i] (без заголовка): блок, смещение и длина; `null` — пусто.
  (int, int, int)? key(int i) {
    final at = (i + 2) * entrySize;
    if (at + entrySize > index.length) {
      return null;
    }
    final blockNumber = indexView.getUint32(at, Endian.little);
    final offset = indexView.getUint32(at + 4, Endian.little);
    final size = entrySize == 10
        ? indexView.getUint16(at + 8, Endian.little)
        : indexView.getUint32(at + 8, Endian.little);

    return size == 0 ? null : (blockNumber, offset, size);
  }

  final records = <ZComRecord>[];
  var i = 0;
  while (i < places.length) {
    final current = key(i);
    if (current == null) {
      i++;
      continue;
    }
    var last = i;
    while (last + 1 < places.length &&
        places[last + 1].book == places[i].book &&
        key(last + 1) == current) {
      last++;
    }
    final (blockNumber, offset, size) = current;
    final bytes = block(blockNumber);
    if (offset + size > bytes.length) {
      throw FormatException(
        'zCom: $testament record at ${_placeName(places[i])} is outside '
        'its block',
      );
    }
    final String text;
    try {
      text = utf8.decode(Uint8List.sublistView(bytes, offset, offset + size));
    } on FormatException {
      throw FormatException(
        'zCom: $testament record at ${_placeName(places[i])} is not UTF-8',
      );
    }
    final start = places[i];
    // Конец — последнее место диапазона со стихом; запись главы в конце
    // диапазона его не удлиняет.
    var end = places[last];
    for (var j = last; j > i && places[j].verse == 0; j--) {
      end = places[j - 1];
    }
    final single = end == start;
    records.add(
      ZComRecord(
        book: start.book,
        chapter: start.chapter,
        verse: start.verse,
        chapterEnd: single || end.chapter == start.chapter ? null : end.chapter,
        verseEnd: single ? null : end.verse,
        text: text,
      ),
    );
    i = last + 1;
  }

  return records;
}

String _placeName(_Place place) =>
    '${place.book} ${place.chapter}:${place.verse}';

Uint8List _bytes(List<int> list) =>
    list is Uint8List ? list : Uint8List.fromList(list);
