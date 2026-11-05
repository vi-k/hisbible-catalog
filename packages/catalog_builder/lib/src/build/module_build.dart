import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/src/build/module_validation.dart';
import 'package:catalog_builder/src/catalog/overrides.dart';
import 'package:catalog_builder/src/ebible/scripts.dart';
import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';

/// Версия сборки в ключе `generator`; равна версии пакета в `pubspec.yaml`.
const builderVersion = '0.2.0';

/// Итог сборки одного модуля.
sealed class BuildOutcome {
  const BuildOutcome();
}

/// Модуль собран и прошёл [validateModule].
final class Built extends BuildOutcome {
  /// Создаёт итог собранного модуля.
  const Built({
    required this.meta,
    required this.path,
    required this.size,
    required this.sha256,
    required this.books,
    required this.warnings,
    this.xtLinked = 0,
    this.xtByHref = 0,
    this.xtUnresolved = 0,
  });

  /// Описание модуля, записанное в файл.
  final ModuleMeta meta;

  /// Путь к файлу модуля.
  final String path;

  /// Размер файла в байтах.
  final int size;

  /// SHA-256 файла, 64 шестнадцатеричные цифры.
  final String sha256;

  /// Число книг Ветхого, Нового Завета и неканонических.
  final ({int ot, int nt, int dc}) books;

  /// Что сборка пропустила или выбросила: книги вне справочника,
  /// выброшенные куски текста, незнакомые маркеры.
  final List<String> warnings;

  /// Сколько `\xt` (элементов, не ссылок) стали ссылками `<x r>`, в том
  /// числе по `link-href`; частично разобранный `\xt` считается разобранным.
  final int xtLinked;

  /// Сколько из них — по `link-href`.
  final int xtByHref;

  /// Сколько `\xt` остались текстом: места из них не разобрались.
  final int xtUnresolved;
}

/// Модуль не собран; файла модуля нет.
final class BuildFailed extends BuildOutcome {
  /// Создаёт итог несобранного модуля.
  const BuildFailed(this.reasons);

  /// Почему модуль не собран.
  final List<String> reasons;
}

/// Собирает модуль Библии [outPath] из архива USFM [usfmZip] перевода [t].
///
/// Каждый `*.usfm` и `*.sfm` архива разбирается [parseUsfm]; книга без
/// номера в справочнике, без стихов или повторная пропускается и попадает
/// в [Built.warnings]. Книги идут по номерам, у языков `ru`, `uk` и `be` —
/// по [BookCatalog.russianOrder]. Схема нумерации каждой книги
/// распознаётся по последним стихам её глав. Сноски нумеруются по книгам
/// подряд. Лицензия берётся из `copr.htm` архива, `created` — дата [now],
/// `version` — [version], по умолчанию `UpdateDate` перевода.
///
/// Файл пишется рядом, в `<outPath>.part`, проверяется [validateModule]
/// и только потом встаёт на место [outPath]. Не прочёлся архив, не
/// записался файл или модуль не прошёл проверку — [BuildFailed], и файла
/// [outPath] сборка не оставляет.
BuildOutcome buildModule(
  EbibleTranslation t,
  File usfmZip,
  String outPath, {
  required Overrides overrides,
  required DateTime now,
  String? version,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(usfmZip.readAsBytesSync());
  } on FileSystemException catch (e) {
    return BuildFailed(['cannot read ${usfmZip.path}: ${e.message}']);
  } on FormatException catch (e) {
    return BuildFailed(['${usfmZip.path} is not a zip: ${e.message}']);
  }
  // Архив распаковывается лениво: битая запись видна только при чтении.
  final UsfmBooks read;
  final String? copyrightPage;
  try {
    read = readUsfmBooks([
      for (final file in archive.files)
        if (file.isFile && _isUsfm(file.name))
          (name: file.name, bytes: file.content as List<int>),
    ]);
    copyrightPage = _copyrightPage(archive);
  } on Object catch (e) {
    return BuildFailed(['cannot read ${usfmZip.path}: $e']);
  }
  if (read.books.isEmpty) {
    return BuildFailed(['no books in ${usfmZip.path}', ...read.warnings]);
  }
  final language = bcp47Of(t.languageCode);
  // Описание берёт письменность и слово «глава» из книг в порядке модуля.
  final books = read.ordered(language);
  final meta = ModuleMeta(
    type: ModuleType.bible,
    abbreviation: overrides.abbreviations[t.translationId] ?? t.translationId,
    name: t.title,
    language: language,
    direction: t.textDirection,
    script: scriptCodeOf(t.script, books.sample()),
    license: licenseOf(copyrightPage, copyright: t.copyright),
    copyright: t.copyright,
    description: t.description,
    source: 'ebible:${t.translationId}',
    sourceUrl: t.publicationUrl,
    version: version ?? t.updateDate,
    created: isoDate(now),
    catalog: 'hisbible',
    catalogId: t.translationId,
    chapterWord: books.chapterLabel,
    generator: 'catalog_builder $builderVersion',
  );

  final partPath = '$outPath.part';
  final part = File(partPath);
  final XtStats xt;
  try {
    part.parent.createSync(recursive: true);
    xt = writeUsfmModule(partPath, meta, books);
  } on Object catch (e) {
    _delete(part);

    return BuildFailed(['cannot write $partPath: $e']);
  }
  final reasons = validateModule(
    partPath,
    t,
    skippedVerses: books.skippedVerses,
  );
  if (reasons.isNotEmpty) {
    _delete(part);

    return BuildFailed(reasons);
  }
  final List<int> bytes;
  try {
    bytes = part.readAsBytesSync();
    part.renameSync(outPath);
  } on FileSystemException catch (e) {
    _delete(part);

    return BuildFailed(['cannot move the module to $outPath: ${e.message}']);
  }

  return Built(
    meta: meta,
    path: outPath,
    size: bytes.length,
    sha256: crypto.sha256.convert(bytes).toString(),
    books: _bookCounts(books.books),
    warnings: books.warnings,
    xtLinked: xt.linked,
    xtByHref: xt.byHref,
    xtUnresolved: xt.unresolved,
  );
}

bool _isUsfm(String name) {
  final lower = name.toLowerCase();

  return lower.endsWith('.usfm') || lower.endsWith('.sfm');
}

// Текст файла архива в UTF-8 без BOM; битая запись — [FormatException].
String _text(ArchiveFile file) =>
    withoutBom(utf8.decode(file.content, allowMalformed: true));

// Страница `copr.htm` архива или `null`.
String? _copyrightPage(Archive archive) {
  for (final file in archive.files) {
    if (file.isFile && file.name.split('/').last.toLowerCase() == 'copr.htm') {
      return _text(file);
    }
  }

  return null;
}

({int ot, int nt, int dc}) _bookCounts(List<UsfmBookEntry> books) {
  var ot = 0;
  var nt = 0;
  var dc = 0;
  for (final book in books) {
    if (book.info.deuterocanonical) {
      dc++;
    } else if (book.info.testament == Testament.old) {
      ot++;
    } else {
      nt++;
    }
  }

  return (ot: ot, nt: nt, dc: dc);
}

void _delete(File file) {
  if (file.existsSync()) {
    file.deleteSync();
  }
}
