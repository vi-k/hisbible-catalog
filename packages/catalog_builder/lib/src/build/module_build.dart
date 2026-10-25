import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/src/build/module_validation.dart';
import 'package:catalog_builder/src/catalog/overrides.dart';
import 'package:catalog_builder/src/ebible/license.dart';
import 'package:catalog_builder/src/ebible/scripts.dart';
import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:catalog_builder/src/usfm/usfm_book.dart';
import 'package:catalog_builder/src/usfm/usfm_parser.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';

/// Версия сборки в ключе `generator`; равна версии пакета в `pubspec.yaml`.
const builderVersion = '0.1.0';

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
}

/// Модуль не собран; файла модуля нет.
final class BuildFailed extends BuildOutcome {
  /// Создаёт итог несобранного модуля.
  const BuildFailed(this.reasons);

  /// Почему модуль не собран.
  final List<String> reasons;
}

/// Языки, у которых книги идут в порядке [BookCatalog.russianOrder].
const _russianOrderLanguages = {'ru', 'uk', 'be'};

/// Собирает модуль Библии [outPath] из архива USFM [usfmZip] перевода [t].
///
/// Каждый `*.usfm` и `*.sfm` архива разбирается [parseUsfm]; книга без
/// номера в справочнике, без стихов или повторная пропускается и попадает
/// в [Built.warnings]. Книги идут по номерам, у языков `ru`, `uk` и `be` —
/// по [BookCatalog.russianOrder]. Схема нумерации каждой книги
/// распознаётся по последним стихам её глав. Сноски нумеруются по книгам
/// подряд. Лицензия берётся из `copr.htm` архива, `created` — дата [now].
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
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(usfmZip.readAsBytesSync());
  } on FileSystemException catch (e) {
    return BuildFailed(['cannot read ${usfmZip.path}: ${e.message}']);
  } on FormatException catch (e) {
    return BuildFailed(['${usfmZip.path} is not a zip: ${e.message}']);
  }
  final warnings = <String>[];
  final books = _readBooks(archive, warnings);
  if (books.isEmpty) {
    return BuildFailed(['no books in ${usfmZip.path}', ...warnings]);
  }
  final language = bcp47Of(t.languageCode);
  final russian = _russianOrderLanguages.contains(language);
  _order(books, russian: russian);
  final meta = ModuleMeta(
    type: ModuleType.bible,
    abbreviation: overrides.abbreviations[t.translationId] ?? t.translationId,
    name: t.title,
    language: language,
    direction: t.textDirection,
    script: scriptCodeOf(t.script, _sample(books)),
    license: licenseOf(_copyrightPage(archive)),
    copyright: t.copyright,
    description: t.description,
    source: 'ebible:${t.translationId}',
    sourceUrl: t.publicationUrl,
    version: t.updateDate,
    created: _isoDate(now),
    catalog: 'hisbible',
    catalogId: t.translationId,
    chapterWord: _filled(books.first.usfm.chapterLabel),
    generator: 'catalog_builder $builderVersion',
  );

  final partPath = '$outPath.part';
  final part = File(partPath);
  try {
    part.parent.createSync(recursive: true);
    _write(partPath, meta, books, warnings, russian: russian);
  } on Exception catch (e) {
    _delete(part);

    return BuildFailed(['cannot write $partPath: $e']);
  }
  final reasons = validateModule(partPath, t);
  if (reasons.isNotEmpty) {
    _delete(part);

    return BuildFailed(reasons);
  }
  final List<int> bytes;
  try {
    bytes = part.renameSync(outPath).readAsBytesSync();
  } on FileSystemException catch (e) {
    _delete(part);

    return BuildFailed(['cannot move the module to $outPath: ${e.message}']);
  }

  return Built(
    meta: meta,
    path: outPath,
    size: bytes.length,
    sha256: crypto.sha256.convert(bytes).toString(),
    books: _bookCounts(books),
    warnings: warnings,
  );
}

// Книга архива с номером справочника.
typedef _Book = ({int number, BookInfo info, UsfmBook usfm});

// Разбирает книги архива по порядку имён; что пропущено — в [warnings].
List<_Book> _readBooks(Archive archive, List<String> warnings) {
  final files = [
    for (final file in archive.files)
      if (file.isFile && _isUsfm(file.name)) file,
  ]..sort((a, b) => a.name.compareTo(b.name));
  final books = <_Book>[];
  final numbers = <int>{};
  for (final file in files) {
    final usfm = parseUsfm(_text(file));
    final code = usfm.code;
    final number = BookCatalog.numberOfCode(code);
    final info = number == null ? null : BookCatalog.byNumber(number);
    if (code.isEmpty) {
      warnings.add('${file.name}: no \\id, skipped');
    } else if (number == null || info == null) {
      warnings.add('$code: not in the book catalog, skipped');
    } else if (!numbers.add(number)) {
      warnings.add('$code: second copy in ${file.name}, skipped');
    } else if (usfm.verses.isEmpty) {
      warnings.add('$code: no verses, skipped');
    } else {
      books.add((number: number, info: info, usfm: usfm));
      if (usfm.droppedFragments > 0) {
        warnings.add('$code: dropped fragments: ${usfm.droppedFragments}');
      }
      if (usfm.unknownMarkers.isNotEmpty) {
        final markers = usfm.unknownMarkers.toList()..sort();
        warnings.add('$code: unknown markers: ${markers.join(', ')}');
      }
    }
  }

  return books;
}

bool _isUsfm(String name) {
  final lower = name.toLowerCase();

  return lower.endsWith('.usfm') || lower.endsWith('.sfm');
}

// Текст файла архива в UTF-8 без BOM.
String _text(ArchiveFile file) {
  final text = utf8.decode(file.content, allowMalformed: true);

  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

// Страница `copr.htm` архива или `null`.
String? _copyrightPage(Archive archive) {
  for (final file in archive.files) {
    if (file.isFile && file.name.split('/').last.toLowerCase() == 'copr.htm') {
      return _text(file);
    }
  }

  return null;
}

// Ставит книги по номерам или, при [russian], по русскому порядку; книги
// вне русского порядка — после него, по номерам.
void _order(List<_Book> books, {required bool russian}) {
  int rank(_Book book) {
    if (!russian) {
      return book.number;
    }
    final index = BookCatalog.russianOrder.indexOf(book.number);

    return index < 0 ? BookCatalog.russianOrder.length + book.number : index;
  }

  books.sort((a, b) => rank(a).compareTo(rank(b)));
}

// Длина выборки текста в знаках: вдвое больше 10 000 букв, которые считает
// [scriptCodeOf], с запасом на пробелы, цифры и знаки.
const _sampleLength = 20000;

// Начало текста модуля для [scriptCodeOf].
String _sample(List<_Book> books) {
  final out = StringBuffer();
  for (final book in books) {
    for (final verse in book.usfm.verses) {
      out
        ..write(plainText(verse.nodes))
        ..write(' ');
      if (out.length >= _sampleLength) {
        return out.toString();
      }
    }
  }

  return out.toString();
}

// Пишет модуль [path]; повторные стихи пропускаются и попадают
// в [warnings].
void _write(
  String path,
  ModuleMeta meta,
  List<_Book> books,
  List<String> warnings, {
  required bool russian,
}) {
  final schemes = Versification.standard.detect({
    for (final book in books) book.number: _lastVerses(book.usfm),
  }, russianFlag: russian);
  final writer = ModuleWriter.create(path, meta);
  try {
    var noteOffset = 0;
    for (final book in books) {
      final usfm = book.usfm;
      writer.addBook(
        number: book.number,
        shortName:
            _filled(usfm.toc3) ?? _filled(usfm.header) ?? book.info.enShort,
        longName:
            _filled(usfm.toc2) ??
            _filled(usfm.header) ??
            _filled(usfm.toc1) ??
            book.info.enLong,
        title: _filled(usfm.toc1),
        scheme: schemes.of(book.number),
      );
      _writeText(writer, book, noteOffset, warnings);
      var lastNote = 0;
      for (final note in usfm.notes) {
        lastNote = note.id > lastNote ? note.id : lastNote;
      }
      noteOffset += lastNote;
    }
    writer.finish();
  } on Object {
    writer.abort();
    rethrow;
  }
}

// Пишет стихи, заголовки и сноски книги; номера сносок сдвинуты на
// [offset].
void _writeText(
  ModuleWriter writer,
  _Book book,
  int offset,
  List<String> warnings,
) {
  final _Book(:number, :usfm) = book;
  final written = <(int, int)>{};
  for (final verse in usfm.verses) {
    if (!written.add((verse.chapter, verse.verse))) {
      warnings.add(
        '${usfm.code} ${verse.chapter}:${verse.verse}: repeated verse, '
        'skipped',
      );
      continue;
    }
    writer.addVerse(
      number,
      verse.chapter,
      verse.verse,
      writeMarkup(_shiftNotes(verse.nodes, offset)),
      verseEnd: verse.verseEnd,
    );
  }
  for (final heading in usfm.headings) {
    writer.addHeading(
      number,
      heading.chapter,
      heading.verse,
      heading.kind,
      heading.level,
      writeMarkup(_shiftNotes(heading.nodes, offset)),
    );
  }
  for (final note in usfm.notes) {
    writer.addFootnote(
      offset + note.id,
      number,
      note.chapter,
      note.verse,
      note.kind,
      note.caller,
      writeMarkup(_shiftNotes(note.nodes, offset)),
    );
  }
}

// Номера сносок [nodes], сдвинутые на [offset].
List<MarkupNode> _shiftNotes(List<MarkupNode> nodes, int offset) {
  if (offset == 0) {
    return nodes;
  }

  return [
    for (final node in nodes)
      switch (node) {
        FootnoteRef(:final id, :final caller) => FootnoteRef(
          id + offset,
          caller,
        ),
        StyledSpan(:final style, :final children) => StyledSpan(
          style,
          _shiftNotes(children, offset),
        ),
        TaggedWord(:final children, :final strong, :final morph) => TaggedWord(
          _shiftNotes(children, offset),
          strong: strong,
          morph: morph,
        ),
        TextRun() || LineBreak() || ParagraphBreak() => node,
      },
  ];
}

// Глава → последний стих; у слитых стихов — последний из них.
Map<int, int> _lastVerses(UsfmBook usfm) {
  final lasts = <int, int>{};
  for (final verse in usfm.verses) {
    final last = verse.verseEnd ?? verse.verse;
    if (last > (lasts[verse.chapter] ?? 0)) {
      lasts[verse.chapter] = last;
    }
  }

  return lasts;
}

({int ot, int nt, int dc}) _bookCounts(List<_Book> books) {
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

String? _filled(String? text) {
  final trimmed = text?.trim();

  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _delete(File file) {
  if (file.existsSync()) {
    file.deleteSync();
  }
}
