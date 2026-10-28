import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/openbible/osis_books.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';

/// Откуда берутся перекрёстные ссылки OpenBible.info.
const openBibleUrl = 'https://a.openbible.info/data/cross-references.zip';

/// Где лежит запись об архиве: пишется первым прогоном и коммитится.
const openBibleLockPath = 'sources/openbible.lock.json';

/// Имя файла ссылок в архиве; остальное из архива не берётся.
const _entryName = 'cross_references.txt';

/// Сколько ссылок записано и сколько строк отброшено, по причинам.
///
/// Каждая отброшенная строка считается один раз, в первой подошедшей по
/// порядку причине: [negative], [unknownBook], [outsideEng], [selfLinks].
final class OpenBibleOutcome {
  /// Создаёт итог сборки.
  const OpenBibleOutcome({
    required this.written,
    required this.negative,
    required this.unknownBook,
    required this.outsideEng,
    required this.selfLinks,
  });

  /// Записано ссылок.
  final int written;

  /// Отброшено с отрицательным весом.
  final int negative;

  /// Отброшено: книга не из 66 кодов [osisBooks].
  final int unknownBook;

  /// Отброшено: места нет в английской нумерации (`eng`) или диапазон
  /// перевёрнут.
  final int outsideEng;

  /// Отброшено: ссылка стиха на самого себя.
  final int selfLinks;
}

/// Собирает модуль ссылок из таблицы [tsv] OpenBible.info и пишет его
/// в [outPath].
///
/// Заголовок и строки на `#` пропускаются; вес меньше нуля, неизвестная
/// книга, место вне нумерации `eng` и ссылка на себя отбрасываются
/// и считаются в итоге. Строка не по форме — [FormatException], файл
/// при этом не трогается. В `meta` — [version] и дата [now].
OpenBibleOutcome buildOpenBible(
  String tsv,
  String outPath, {
  required String version,
  required DateTime now,
}) {
  final lastVerses = <int, Map<int, int>>{};
  // Место с известной книгой: зовётся после проверки на `null`.
  bool exists(_Place place) {
    final book = place.book!;
    final last = lastVerses.putIfAbsent(
      book,
      () => Versification.standard.lastVerses(VerseScheme.eng, book),
    )[place.chapter];

    return last != null && place.verse >= 1 && place.verse <= last;
  }

  var negative = 0;
  var unknownBook = 0;
  var outsideEng = 0;
  var selfLinks = 0;
  final links = <(int, CrossRef)>[];
  var lineNumber = 0;
  var header = true;
  for (final line in const LineSplitter().convert(tsv)) {
    lineNumber++;
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (header) {
      header = false;
      if (trimmed.startsWith('From Verse')) {
        continue;
      }
    }
    final fields = line.split('\t');
    final votes = fields.length < 3 ? null : int.tryParse(fields[2].trim());
    if (votes == null) {
      throw FormatException('line $lineNumber is not a link: $line');
    }
    final from = _parsePlace(fields[0], lineNumber);
    final target = fields[1].split('-');
    if (target.length > 2) {
      throw FormatException('line $lineNumber is not a link: $line');
    }
    final to = _parsePlace(target.first, lineNumber);
    final toEnd = target.length == 2
        ? _parsePlace(target.last, lineNumber)
        : null;
    if (votes < 0) {
      negative++;
    } else if (from.book == null ||
        to.book == null ||
        (toEnd != null && toEnd.book == null)) {
      unknownBook++;
    } else if (toEnd != null && toEnd.book != to.book) {
      outsideEng++;
    } else if (!exists(from) ||
        !exists(to) ||
        (toEnd != null && (!exists(toEnd) || _before(toEnd, to)))) {
      outsideEng++;
    } else if (toEnd == null &&
        from.book == to.book &&
        from.chapter == to.chapter &&
        from.verse == to.verse) {
      selfLinks++;
    } else {
      // Диапазон в пределах одного стиха — просто стих.
      final range = toEnd != null && !_samePlace(to, toEnd) ? toEnd : null;
      links.add((
        lineNumber,
        CrossRef(
          book: from.book!,
          chapter: from.chapter,
          verse: from.verse,
          toBook: to.book!,
          toChapter: to.chapter,
          toVerse: to.verse,
          toChapterEnd: range != null && range.chapter != to.chapter
              ? range.chapter
              : null,
          toVerseEnd: range?.verse,
          votes: votes,
        ),
      ));
    }
  }

  // Порядок книг справочника, затем глава, стих, вес по убыванию; равные
  // остаются в порядке строк.
  final order = {
    for (final (i, info) in BookCatalog.all.indexed) info.number: i,
  };
  links.sort((a, b) {
    final x = a.$2;
    final y = b.$2;
    final byPlace = [
      order[x.book]!.compareTo(order[y.book]!),
      x.chapter.compareTo(y.chapter),
      x.verse.compareTo(y.verse),
      y.votes.compareTo(x.votes),
      a.$1.compareTo(b.$1),
    ].firstWhere((c) => c != 0, orElse: () => 0);

    return byPlace;
  });

  final meta = ModuleMeta(
    type: ModuleType.crossReferences,
    abbreviation: 'OpenBible',
    name: 'OpenBible.info',
    language: 'und',
    direction: WritingDirection.ltr,
    license: 'CC-BY-4.0',
    copyright: 'OpenBible.info, CC BY',
    source: 'openbible',
    sourceUrl: 'https://www.openbible.info/labs/cross-references/',
    version: version,
    created: isoDate(now),
    numbering: VerseScheme.eng.name,
    generator: 'catalog_builder $builderVersion',
  );
  final partPath = '$outPath.part';
  final part = File(partPath);
  part.parent.createSync(recursive: true);
  final writer = ModuleWriter.create(partPath, meta);
  try {
    for (final (_, link) in links) {
      writer.addCrossref(link);
    }
    writer.finish();
    part.renameSync(outPath);
  } on Object {
    writer.abort();
    if (part.existsSync()) {
      part.deleteSync();
    }
    rethrow;
  }

  return OpenBibleOutcome(
    written: links.length,
    negative: negative,
    unknownBook: unknownBook,
    outsideEng: outsideEng,
    selfLinks: selfLinks,
  );
}

/// Качает архив ссылок OpenBible.info, сверяет его с записью
/// [lockPath] и пишет модуль в [outPath]. Возвращает код выхода.
///
/// Первый прогон пишет [lockPath]. Архив с другой sha256 — отказ (код 1),
/// запись и модуль остаются как были; новую версию данных принимает
/// [acceptNewSource]. Версия модуля — дата `Last-Modified` архива, она
/// хранится в записи: прогон с прежним архивом версию не меняет. Нет
/// `Last-Modified` у нового архива — ошибка. Из архива берётся только
/// `cross_references.txt`, в памяти.
Future<int> runOpenBible(
  String outPath, {
  required HeaderFetcher fetcher,
  required bool acceptNewSource,
  String lockPath = openBibleLockPath,
  DateTime? now,
  StringSink? out,
  StringSink? err,
}) async {
  final sink = out ?? stdout;
  final errSink = err ?? stderr;
  final time = (now ?? DateTime.now()).toUtc();
  try {
    final lockFile = File(lockPath);
    final locked = lockFile.existsSync()
        ? _OpenBibleLock.parse(lockFile.readAsStringSync())
        : null;
    final file = await fetcher.getFile(Uri.parse(openBibleUrl));
    final sha256 = crypto.sha256.convert(file.bytes).toString();
    final String version;
    if (locked != null && locked.sha256 == sha256) {
      version = locked.lastModified;
    } else if (locked != null && !acceptNewSource) {
      errSink.writeln(
        'the OpenBible archive changed: sha256 $sha256, locked '
        '${locked.sha256}; check it and run again with --accept-new-source',
      );

      return 1;
    } else {
      final modified = file.lastModified;
      if (modified == null) {
        errSink.writeln(
          'the OpenBible server sent no Last-Modified: the module version '
          'has no date',
        );

        return 1;
      }
      version = isoDate(modified.toUtc());
    }
    final tsv = _readEntry(file.bytes);
    final outcome = buildOpenBible(tsv, outPath, version: version, now: time);
    final size = File(outPath).lengthSync();
    final lock = _OpenBibleLock(
      url: openBibleUrl,
      sha256: sha256,
      lastModified: version,
      fetched: locked != null && locked.sha256 == sha256
          ? locked.fetched
          : isoDate(time),
    );
    lockFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(lock.toJson());
    sink
      ..writeln('wrote $outPath')
      ..writeln('wrote $lockPath')
      ..writeln('version $version')
      ..writeln('size $size')
      ..writeln(
        'sha256 '
        '${crypto.sha256.convert(File(outPath).readAsBytesSync())}',
      )
      ..writeln(
        'links ${outcome.written}, negative ${outcome.negative}, '
        'unknown book ${outcome.unknownBook}, '
        'outside eng ${outcome.outsideEng}, self ${outcome.selfLinks}',
      );

    return 0;
  } on Object catch (e) {
    errSink.writeln('openbible build failed: $e');

    return 1;
  }
}

// Текст `cross_references.txt` из архива [bytes].
String _readEntry(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    if (file.isFile && file.name == _entryName) {
      return utf8.decode(file.content, allowMalformed: false);
    }
  }
  throw const FormatException('no $_entryName in the OpenBible archive');
}

// Место OSIS `Book.chapter.verse`; [book] — номер справочника или `null`,
// если код не из [osisBooks].
typedef _Place = ({int? book, int chapter, int verse});

final _placePattern = RegExp(r'^\s*(\w+)\.(\d{1,6})\.(\d{1,6})\s*$');

_Place _parsePlace(String text, int lineNumber) {
  final match = _placePattern.firstMatch(text);
  if (match == null) {
    throw FormatException('line $lineNumber: "$text" is not a place');
  }

  return (
    book: osisBooks[match[1]],
    chapter: int.parse(match[2]!),
    verse: int.parse(match[3]!),
  );
}

// [a] раньше [b] в пределах одной книги.
bool _before(_Place a, _Place b) =>
    a.chapter < b.chapter || (a.chapter == b.chapter && a.verse < b.verse);

bool _samePlace(_Place a, _Place b) =>
    a.chapter == b.chapter && a.verse == b.verse;

// Запись `sources/openbible.lock.json`.
final class _OpenBibleLock {
  const _OpenBibleLock({
    required this.url,
    required this.sha256,
    required this.lastModified,
    required this.fetched,
  });

  factory _OpenBibleLock.parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('openbible.lock.json is not JSON: ${e.message}');
    }
    if (root is Map<String, Object?> &&
        root['url'] is String &&
        root['sha256'] is String &&
        root['lastModified'] is String &&
        root['fetched'] is String) {
      return _OpenBibleLock(
        url: root['url']! as String,
        sha256: root['sha256']! as String,
        lastModified: root['lastModified']! as String,
        fetched: root['fetched']! as String,
      );
    }
    throw const FormatException('openbible.lock.json has the wrong form');
  }

  final String url;
  final String sha256;
  final String lastModified;
  final String fetched;

  String toJson() {
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert({
      'url': url,
      'sha256': sha256,
      'lastModified': lastModified,
      'fetched': fetched,
    });

    return '$json\n';
  }
}
