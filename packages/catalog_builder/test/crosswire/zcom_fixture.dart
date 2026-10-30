import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:catalog_builder/catalog_builder.dart';

/// Маленький модуль zCom для тестов: записи по местам KJV.
final class ZComFixture {
  // Завет → номер места (без заголовка) → номер записи в [_texts].
  final _places = <String, Map<int, int>>{'ot': {}, 'nt': {}};
  final _texts = <String>[];

  /// Кладёт запись [text] на место [osis] [chapter]:[verse] и, если дан
  /// [verseEnd], на все места до него в той же главе.
  void put(String osis, int chapter, int verse, String text, {int? verseEnd}) {
    _texts.add(text);
    final record = _texts.length - 1;
    for (var v = verse; v <= (verseEnd ?? verse); v++) {
      final (testament, index) = placeIndex(osis, chapter, v);
      _places[testament]![index] = record;
    }
  }

  /// Файлы каталога данных: `ot.<kind>zs`, `.zv`, `.zz` и то же для `nt`;
  /// у завета без записей файлов нет, если не [allTestaments]. В блоке —
  /// не больше [perBlock] записей.
  Map<String, List<int>> files({
    int entrySize = 10,
    String kind = 'b',
    int perBlock = 2,
    bool allTestaments = false,
  }) {
    final files = <String, List<int>>{};
    for (final testament in ['ot', 'nt']) {
      final places = _places[testament]!;
      if (places.isEmpty && !allTestaments) {
        continue;
      }
      final count = testamentPlaces(testament) + 2;
      final index = ByteData(count * entrySize);
      final blockIndex = BytesBuilder();
      final data = BytesBuilder();
      // Запись → (блок, смещение, длина).
      final located = <int, (int, int, int)>{};
      final records = places.values.toSet().toList()..sort();
      for (var start = 0; start < records.length; start += perBlock) {
        final block = BytesBuilder();
        for (final record in records.skip(start).take(perBlock)) {
          final bytes = utf8.encode(_texts[record]);
          located[record] = (start ~/ perBlock, block.length, bytes.length);
          block.add(bytes);
        }
        final raw = block.takeBytes();
        final packed = zlib.encode(raw);
        final entry = ByteData(12)
          ..setUint32(0, data.length, Endian.little)
          ..setUint32(4, packed.length, Endian.little)
          ..setUint32(8, raw.length, Endian.little);
        blockIndex.add(entry.buffer.asUint8List());
        data.add(packed);
      }
      for (final MapEntry(key: place, value: record) in places.entries) {
        final (block, offset, size) = located[record]!;
        final at = (place + 2) * entrySize;
        index
          ..setUint32(at, block, Endian.little)
          ..setUint32(at + 4, offset, Endian.little);
        if (entrySize == 10) {
          index.setUint16(at + 8, size, Endian.little);
        } else {
          index.setUint32(at + 8, size, Endian.little);
        }
      }
      files['$testament.${kind}zv'] = index.buffer.asUint8List();
      files['$testament.${kind}zs'] = blockIndex.takeBytes();
      files['$testament.${kind}zz'] = data.takeBytes();
    }

    return files;
  }
}

/// Число мест завета без двух записей заголовка.
int testamentPlaces(String testament) {
  final books = testament == 'ot'
      ? kjvCanon.take(kjvOldTestamentBooks)
      : kjvCanon.skip(kjvOldTestamentBooks);

  return books.fold(
    0,
    (sum, book) =>
        sum + 1 + book.verses.fold(0, (sum, verses) => sum + 1 + verses),
  );
}

/// Завет и номер места (без заголовка) книги [osis] [chapter]:[verse];
/// глава 0 — запись книги, стих 0 — запись главы.
(String, int) placeIndex(String osis, int chapter, int verse) {
  var index = 0;
  for (final (i, book) in kjvCanon.indexed) {
    if (i == kjvOldTestamentBooks) {
      index = 0;
    }
    if (book.osis == osis) {
      if (chapter > 0) {
        index++;
        for (var c = 1; c < chapter; c++) {
          index += 1 + book.verses[c - 1];
        }
        index += verse;
      }

      return (i < kjvOldTestamentBooks ? 'ot' : 'nt', index);
    }
    index += 1 + book.verses.fold(0, (sum, verses) => sum + 1 + verses);
  }
  throw ArgumentError.value(osis, 'osis');
}

/// Архив модуля CrossWire: `mods.d/<имя>.conf` и файлы [files]
/// в `modules/comments/zcom/<имя>/`.
Uint8List crosswireZip(
  String module,
  Map<String, List<int>> files, {
  String modDrv = 'zCom',
  String license = 'Public Domain',
  String version = '2021-10-19',
}) {
  final lower = module.toLowerCase();
  final conf =
      '## Sword module configuration file\n'
      '[$module]\n'
      'Description=$module Commentary\n'
      'DataPath=./modules/comments/zcom/$lower/\n'
      'ModDrv=$modDrv\n'
      'SourceType=OSIS\n'
      'Encoding=UTF-8\n'
      'CompressType=ZIP\n'
      'BlockType=BOOK\n'
      'Versification=KJV\n'
      'GlobalOptionFilter=OSISHeadings\n'
      'GlobalOptionFilter=OSISScripref\n'
      r'About=First paragraph.\par Second paragraph.'
      '\n'
      'SwordVersionDate=$version\n'
      'DistributionLicense=$license\n'
      'TextSource=https://example.org/$lower\n';
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('mods.d/$lower.conf', utf8.encode(conf)));
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(
      ArchiveFile.bytes('modules/comments/zcom/$lower/$key', value),
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
