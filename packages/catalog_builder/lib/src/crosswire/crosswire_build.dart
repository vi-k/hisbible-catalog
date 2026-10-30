import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/crosswire/articles.dart';
import 'package:catalog_builder/src/crosswire/osis_html.dart';
import 'package:catalog_builder/src/crosswire/zcom.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';

/// Откуда берутся архивы модулей CrossWire: `<адрес><модуль>.zip`.
const crosswireUrlBase =
    'https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/';

/// Где лежит запись об архивах CrossWire: пишется первым прогоном каждого
/// модуля и коммитится.
const crosswireLockPath = 'sources/crosswire.lock.json';

/// Модули толкований CrossWire, которые умеет собирать сборка, и как в них
/// отмечено начало толкования стиха 1 ([ArticleMarker]).
const Map<String, ArticleMarker> crosswireModules = {
  'Clarke': ArticleMarker.verseLabel,
  'KD': ArticleMarker.verseReference,
};

/// Адрес архива модуля CrossWire [module].
Uri crosswireUrl(String module) => Uri.parse('$crosswireUrlBase$module.zip');

/// Итог сборки модуля толкований CrossWire.
final class CrossWireOutcome {
  /// Создаёт итог.
  const CrossWireOutcome({
    required this.version,
    required this.records,
    required this.comments,
    required this.bookArticles,
    required this.chapterArticles,
    required this.split,
    required this.whole,
    required this.shifted,
    required this.empty,
    required this.links,
    required this.unresolved,
    required this.notes,
  });

  /// Версия модуля: `SwordVersionDate` из `.conf`.
  final String version;

  /// Записей zCom (диапазон — одна запись).
  final int records;

  /// Записано толкований мест.
  final int comments;

  /// Записано статей к книге.
  final int bookArticles;

  /// Записано статей к главе.
  final int chapterArticles;

  /// Записей стиха 1, поделённых на статью и толкование стиха.
  final int split;

  /// Записей стиха 1, целиком ставших статьёй.
  final int whole;

  /// Толкований, чьё начало сдвинуто со стиха 2 на стих 1.
  final int shifted;

  /// Частей без текста: не записаны.
  final int empty;

  /// Ссылок `ref:`.
  final int links;

  /// Ссылок, оставшихся текстом.
  final int unresolved;

  /// Сносок.
  final int notes;
}

/// Собирает модуль толкований CrossWire [module] из архива [zip] и пишет его
/// в [outPath].
///
/// Из архива берутся `mods.d/*.conf` модуля и файлы его `DataPath`.
/// Модуль — zCom или zCom4 с разметкой OSIS, версификацией KJV и лицензией
/// `Public Domain`; иное — [FormatException], файл при этом не трогается.
/// В `meta` — версия `SwordVersionDate` и дата [now].
CrossWireOutcome buildCrossWire(
  List<int> zip,
  String module,
  String outPath, {
  required DateTime now,
}) {
  final marker = crosswireModules[module];
  if (marker == null) {
    throw ArgumentError.value(module, 'module', 'not a known CrossWire module');
  }
  final archive = ZipDecoder().decodeBytes(zip);
  final conf = _findConf(archive, module);
  final entrySize = switch (conf['ModDrv']) {
    'zCom' => 10,
    'zCom4' => 12,
    final other => throw FormatException(
      '$module: ModDrv $other is not zCom or zCom4',
    ),
  };
  for (final (key, expected, fallback) in [
    ('SourceType', 'OSIS', null),
    ('Encoding', 'UTF-8', null),
    ('CompressType', 'ZIP', null),
    ('Versification', 'KJV', 'KJV'),
    ('DistributionLicense', 'Public Domain', null),
  ]) {
    final value = conf[key] ?? fallback;
    if (value != expected) {
      throw FormatException('$module: $key is $value, not $expected');
    }
  }
  final version = conf['SwordVersionDate'] ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(version) ||
      moduleVersionDate(version) == null) {
    throw FormatException('$module: SwordVersionDate "$version" is not a date');
  }
  final name = conf['Description'];
  if (name == null || name.isEmpty) {
    throw FormatException('$module: no Description');
  }
  var dataPath = conf['DataPath'] ?? '';
  dataPath = dataPath.replaceFirst(RegExp(r'^\./'), '');
  if (dataPath.isEmpty || dataPath.contains('..')) {
    throw FormatException('$module: DataPath "$dataPath" is not usable');
  }
  if (!dataPath.endsWith('/')) {
    dataPath = '$dataPath/';
  }
  final files = <String, List<int>>{
    for (final file in archive)
      if (file.isFile &&
          file.name.startsWith(dataPath) &&
          !file.name.substring(dataPath.length).contains('/'))
        file.name.substring(dataPath.length): file.content,
  };
  final records = readZCom(files, indexEntrySize: entrySize);
  final (:parts, :split, :whole, :shifted) = splitArticles(records, marker);

  final meta = ModuleMeta(
    type: ModuleType.commentaries,
    abbreviation: module,
    name: name,
    language: 'en',
    direction: WritingDirection.ltr,
    script: 'Latn',
    license: 'PD',
    copyright: 'Public Domain',
    description: _firstParagraph(conf['About']),
    source: 'crosswire:$module',
    sourceUrl: conf['TextSource'],
    version: version,
    created: isoDate(now),
    numbering: VerseScheme.eng.name,
    generator: 'catalog_builder $builderVersion',
  );
  var comments = 0;
  var bookArticles = 0;
  var chapterArticles = 0;
  var empty = 0;
  var links = 0;
  var unresolved = 0;
  var notes = 0;
  final partPath = '$outPath.part';
  final part = File(partPath);
  part.parent.createSync(recursive: true);
  final writer = ModuleWriter.create(partPath, meta);
  try {
    for (final piece in parts) {
      final html = osisToHtml(piece.osis);
      links += html.links;
      unresolved += html.unresolved;
      notes += html.notes;
      if (html.html.isEmpty) {
        empty++;
        continue;
      }
      switch (piece.kind) {
        case CommentPartKind.comment:
          comments++;
        case CommentPartKind.bookArticle:
          bookArticles++;
        case CommentPartKind.chapterArticle:
          chapterArticles++;
      }
      writer.addComment(
        piece.book,
        piece.chapter,
        piece.verse,
        html.html,
        chapterEnd: piece.chapterEnd,
        verseEnd: piece.verseEnd,
      );
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

  return CrossWireOutcome(
    version: version,
    records: records.length,
    comments: comments,
    bookArticles: bookArticles,
    chapterArticles: chapterArticles,
    split: split,
    whole: whole,
    shifted: shifted,
    empty: empty,
    links: links,
    unresolved: unresolved,
    notes: notes,
  );
}

/// Качает архив модуля CrossWire [module], сверяет его с записью
/// [lockPath] и пишет модуль толкований в [outPath]. Возвращает код выхода.
///
/// Модуль — из [crosswireModules], иначе отказ (код 1). Первый прогон
/// модуля пишет его запись в [lockPath]: адрес, sha256, версию и дату
/// получения. Архив с другой sha256 — отказ (код 1), запись и модуль
/// остаются как были; новый архив принимает [acceptNewSource]. Записи
/// других модулей не меняются.
Future<int> runCrossWire(
  String module,
  String outPath, {
  required HeaderFetcher fetcher,
  required bool acceptNewSource,
  String lockPath = crosswireLockPath,
  DateTime? now,
  StringSink? out,
  StringSink? err,
}) async {
  final sink = out ?? stdout;
  final errSink = err ?? stderr;
  final time = (now ?? DateTime.now()).toUtc();
  if (!crosswireModules.containsKey(module)) {
    errSink.writeln(
      'unknown CrossWire module $module; known: '
      '${crosswireModules.keys.join(', ')}',
    );

    return 1;
  }
  try {
    final lockFile = File(lockPath);
    final lock = lockFile.existsSync()
        ? _parseLock(lockFile.readAsStringSync())
        : <String, _LockEntry>{};
    final locked = lock[module];
    final url = crosswireUrl(module);
    final file = await fetcher.getFile(url);
    final sha256 = crypto.sha256.convert(file.bytes).toString();
    final same = locked != null && locked.sha256 == sha256;
    if (locked != null && !same && !acceptNewSource) {
      errSink.writeln(
        'the CrossWire archive of $module changed: sha256 $sha256, locked '
        '${locked.sha256}; check it and run again with --accept-new-source',
      );

      return 1;
    }
    final outcome = buildCrossWire(file.bytes, module, outPath, now: time);
    final size = File(outPath).lengthSync();
    lock[module] = _LockEntry(
      url: url.toString(),
      sha256: sha256,
      version: outcome.version,
      fetched: same ? locked.fetched : isoDate(time),
    );
    lockFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_lockToJson(lock));
    sink
      ..writeln('wrote $outPath')
      ..writeln('wrote $lockPath')
      ..writeln('version ${outcome.version}')
      ..writeln('size $size')
      ..writeln(
        'sha256 '
        '${crypto.sha256.convert(File(outPath).readAsBytesSync())}',
      )
      ..writeln(
        'records ${outcome.records}, comments ${outcome.comments}, '
        'book articles ${outcome.bookArticles}, '
        'chapter articles ${outcome.chapterArticles}, '
        'empty ${outcome.empty}',
      )
      ..writeln(
        'verse 1 split ${outcome.split}, whole articles ${outcome.whole}, '
        'shifted to verse 1 ${outcome.shifted}',
      )
      ..writeln(
        'links ${outcome.links}, unresolved ${outcome.unresolved}, '
        'notes ${outcome.notes}',
      );

    return 0;
  } on Object catch (e) {
    errSink.writeln('crosswire build of $module failed: $e');

    return 1;
  }
}

// Ключи `.conf` модуля [module] из архива: первое значение каждого ключа.
Map<String, String> _findConf(Archive archive, String module) {
  for (final file in archive) {
    if (!file.isFile ||
        !file.name.startsWith('mods.d/') ||
        !file.name.endsWith('.conf')) {
      continue;
    }
    final conf = parseSwordConf(utf8.decode(file.content));
    if (conf.section == module) {
      return conf.values;
    }
  }
  throw FormatException('no mods.d/*.conf of $module in the archive');
}

/// Разбирает `.conf` модуля SWORD: имя модуля из `[…]` и ключи.
///
/// Строки на `#` пропускаются; строка, которая кончается `\`, продолжается
/// следующей. У повторённого ключа берётся первое значение. Нет `[…]` —
/// [FormatException].
({String section, Map<String, String> values}) parseSwordConf(String text) {
  String? section;
  final values = <String, String>{};
  final lines = const LineSplitter().convert(withoutBom(text));
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    while (line.endsWith(r'\') && i + 1 < lines.length) {
      line = '${line.substring(0, line.length - 1)}\n${lines[++i]}';
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (section == null) {
      final match = RegExp(r'^\[(.+)\]$').firstMatch(trimmed);
      if (match != null) {
        section = match[1]!.trim();
      }
      continue;
    }
    final at = line.indexOf('=');
    if (at <= 0) {
      continue;
    }
    values.putIfAbsent(
      line.substring(0, at).trim(),
      () => line.substring(at + 1).trim(),
    );
  }
  if (section == null) {
    throw const FormatException('the .conf has no [module] line');
  }

  return (section: section, values: values);
}

// Первый абзац `About`: до первого `\par` RTF.
String? _firstParagraph(String? about) {
  if (about == null) {
    return null;
  }
  final first = about.split(r'\par').first.trim();

  return first.isEmpty ? null : first;
}

// Запись модуля в `sources/crosswire.lock.json`.
final class _LockEntry {
  const _LockEntry({
    required this.url,
    required this.sha256,
    required this.version,
    required this.fetched,
  });

  final String url;
  final String sha256;
  final String version;
  final String fetched;
}

Map<String, _LockEntry> _parseLock(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('crosswire.lock.json is not JSON: ${e.message}');
  }
  if (root is! Map<String, Object?>) {
    throw const FormatException('crosswire.lock.json has the wrong form');
  }

  return {
    for (final MapEntry(:key, :value) in root.entries)
      key: switch (value) {
        {
          'url': final String url,
          'sha256': final String sha256,
          'version': final String version,
          'fetched': final String fetched,
        } =>
          _LockEntry(
            url: url,
            sha256: sha256,
            version: version,
            fetched: fetched,
          ),
        _ => throw FormatException(
          'crosswire.lock.json: the entry of $key has the wrong form',
        ),
      },
  };
}

String _lockToJson(Map<String, _LockEntry> lock) {
  const encoder = JsonEncoder.withIndent('  ');
  final keys = lock.keys.toList()..sort();
  final json = encoder.convert({
    for (final key in keys)
      key: {
        'url': lock[key]!.url,
        'sha256': lock[key]!.sha256,
        'version': lock[key]!.version,
        'fetched': lock[key]!.fetched,
      },
  });

  return '$json\n';
}
