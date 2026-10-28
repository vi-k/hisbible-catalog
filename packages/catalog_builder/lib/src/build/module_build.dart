import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog_builder/src/build/module_validation.dart';
import 'package:catalog_builder/src/catalog/overrides.dart';
import 'package:catalog_builder/src/ebible/license.dart';
import 'package:catalog_builder/src/ebible/scripts.dart';
import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:catalog_builder/src/usfm/usfm_book.dart';
import 'package:catalog_builder/src/usfm/usfm_parser.dart';
import 'package:catalog_builder/src/usfm/xt_links.dart';
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

/// Языки, у которых книги идут в порядке [BookCatalog.russianOrder].
const _russianOrderLanguages = {'ru', 'uk', 'be'};

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
  final warnings = <String>[];
  // Архив распаковывается лениво: битая запись видна только при чтении.
  final List<_Book> books;
  final int skippedVerses;
  final String? copyrightPage;
  try {
    (:books, :skippedVerses) = _readBooks(archive, warnings);
    copyrightPage = _copyrightPage(archive);
  } on Object catch (e) {
    return BuildFailed(['cannot read ${usfmZip.path}: $e']);
  }
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
    license: licenseOf(copyrightPage, copyright: t.copyright),
    copyright: t.copyright,
    description: t.description,
    source: 'ebible:${t.translationId}',
    sourceUrl: t.publicationUrl,
    version: version ?? t.updateDate,
    created: isoDate(now),
    catalog: 'hisbible',
    catalogId: t.translationId,
    chapterWord: _filled(books.first.usfm.chapterLabel),
    generator: 'catalog_builder $builderVersion',
  );

  final partPath = '$outPath.part';
  final part = File(partPath);
  final XtStats xt;
  try {
    part.parent.createSync(recursive: true);
    xt = _write(
      partPath,
      meta,
      books,
      warnings,
      russian: russian,
      language: language,
    );
  } on Object catch (e) {
    _delete(part);

    return BuildFailed(['cannot write $partPath: $e']);
  }
  final reasons = validateModule(partPath, t, skippedVerses: skippedVerses);
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
    books: _bookCounts(books),
    warnings: warnings,
    xtLinked: xt.linked,
    xtByHref: xt.byHref,
    xtUnresolved: xt.unresolved,
  );
}

// Книга архива с номером справочника.
typedef _Book = ({int number, BookInfo info, UsfmBook usfm});

// Разбирает книги архива по порядку имён; что пропущено — в [warnings].
// `skippedVerses` — стихи книг вне справочника: `translations.csv` их
// считает, а в модуль они не идут.
({List<_Book> books, int skippedVerses}) _readBooks(
  Archive archive,
  List<String> warnings,
) {
  final files = [
    for (final file in archive.files)
      if (file.isFile && _isUsfm(file.name)) file,
  ]..sort((a, b) => a.name.compareTo(b.name));
  final books = <_Book>[];
  var skippedVerses = 0;
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
      skippedVerses += usfm.verses.length;
    } else if (usfm.verses.isEmpty) {
      warnings.add('$code: no verses in ${file.name}, skipped');
    } else if (!numbers.add(number)) {
      warnings.add('$code: second copy in ${file.name}, skipped');
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

  return (books: books, skippedVerses: skippedVerses);
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

// Короткое название книги: `\toc3`. У русского и английского перевода,
// где `\toc3` нет или в нём полное название (без учёта регистра), —
// сокращение справочника («Быт», «Gen»; решение владельца 2026-10-26).
String _shortName(_Book book, String language) {
  final usfm = book.usfm;
  final toc3 = _filled(usfm.toc3);
  final full = {
    usfm.header,
    usfm.toc1,
    usfm.toc2,
  }.map(_filled).nonNulls.map((name) => name.toLowerCase()).toSet();
  final ours = switch (language.split('-').first) {
    'ru' => book.info.ruShort,
    'en' => book.info.enShort,
    _ => null,
  };
  if (ours != null && (toc3 == null || full.contains(toc3.toLowerCase()))) {
    return ours;
  }

  return toc3 ?? _filled(usfm.header) ?? book.info.enShort;
}

// Пишет модуль [path]; повторные стихи и стихи с номерами вне границ
// формата пропускаются и попадают в [warnings]. Возвращает счётчики
// ссылок из `\xt`.
XtStats _write(
  String path,
  ModuleMeta meta,
  List<_Book> books,
  List<String> warnings, {
  required bool russian,
  required String language,
}) {
  final skipped = {for (final book in books) book.number: _skipped(book.usfm)};
  final ends = {
    for (final book in books) book.number: _verseEnds(book.usfm, warnings),
  };
  final schemes = Versification.standard.detect({
    for (final book in books)
      book.number: _lastVerses(
        book.usfm,
        ends[book.number]!,
        skipped[book.number]!.outOfRange,
      ),
  }, russianFlag: russian);
  final names = RefBooks.of([
    for (final book in books)
      (
        number: book.number,
        shortName: _shortName(book, language),
        longName: _longName(book),
        toc2: book.usfm.toc2,
        toc3: book.usfm.toc3,
      ),
  ]);
  // Последние стихи глав по схеме каждой книги модуля.
  final lastVerses = {
    for (final book in books)
      book.number: Versification.standard.lastVerses(
        schemes.of(book.number),
        book.number,
      ),
  };
  bool exists(RefRange place) {
    for (final ref in [place.start, ?place.end]) {
      final last = lastVerses[ref.book]?[ref.chapter];
      if (last == null || ref.verse > last) {
        return false;
      }
    }

    return true;
  }

  final xt = XtStats();
  final writer = ModuleWriter.create(path, meta);
  try {
    var noteOffset = 0;
    for (final book in books) {
      final usfm = book.usfm;
      writer.addBook(
        number: book.number,
        shortName: _shortName(book, language),
        longName: _longName(book),
        title: _filled(usfm.toc1),
        scheme: schemes.of(book.number),
      );
      _writeText(
        writer,
        book,
        ends[book.number]!,
        skipped[book.number]!,
        noteOffset,
        warnings,
        names: names,
        exists: exists,
        xt: xt,
      );
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

  return xt;
}

// Полное название книги: `\toc2`, потом `\h`, `\toc1` и справочник.
String _longName(_Book book) =>
    _filled(book.usfm.toc2) ??
    _filled(book.usfm.header) ??
    _filled(book.usfm.toc1) ??
    book.info.enLong;

// Пишет стихи, заголовки и сноски книги; последний из слитых стихов —
// из [ends], номера сносок сдвинуты на [offset]. Стихи из [skipped]
// пропускаются вместе со своими заголовками и сносками. Места из `\xt`
// сносок разбираются по названиям [names] и проверяются [exists];
// счётчики идут в [xt].
void _writeText(
  ModuleWriter writer,
  _Book book,
  Map<UsfmVerse, int?> ends,
  _Skipped skipped,
  int offset,
  List<String> warnings, {
  required RefBooks names,
  required bool Function(RefRange place) exists,
  required XtStats xt,
}) {
  final _Book(:number, :usfm) = book;
  for (final verse in usfm.verses) {
    final place = '${usfm.code} ${verse.chapter}:${verse.verse}';
    if (skipped.outOfRange.contains(verse)) {
      warnings.add(
        verse.chapter > maxChapterNumber
            ? '$place: chapter above $maxChapterNumber, skipped'
            : '$place: verse above $maxVerseNumber, skipped',
      );
    } else if (skipped.repeated.contains(verse)) {
      warnings.add('$place: repeated verse, skipped');
    }
  }
  for (final verse in usfm.verses) {
    if (skipped.repeated.contains(verse) ||
        skipped.outOfRange.contains(verse)) {
      continue;
    }
    writer.addVerse(
      number,
      verse.chapter,
      verse.verse,
      writeMarkup(_shiftNotes(verse.nodes, offset)),
      verseEnd: ends[verse],
    );
  }
  for (final heading in usfm.headings) {
    if (skipped.headings.contains(heading)) {
      continue;
    }
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
    if (skipped.notes.contains(note.id)) {
      continue;
    }
    writer.addFootnote(
      offset + note.id,
      number,
      note.chapter,
      note.verse,
      note.kind,
      note.caller,
      writeMarkup(
        _shiftNotes(
          resolveXtLinks(
            note.nodes,
            names,
            book: number,
            chapter: note.chapter,
            exists: exists,
            stats: xt,
          ),
          offset,
        ),
      ),
    );
  }
}

// Стихи книги, которые не пишутся, их заголовки и номера сносок в тех
// и других.
typedef _Skipped = ({
  Set<UsfmVerse> repeated,
  Set<UsfmVerse> outOfRange,
  Set<UsfmHeading> headings,
  Set<int> notes,
});

// Пропускаемые стихи книги: повторные (тот же номер главы и стиха, что
// у стиха раньше) и с номерами вне границ формата (глава больше
// [maxChapterNumber] или стих больше [maxVerseNumber]); с их заголовками
// и сносками.
//
// Разбор добавляет заголовки в начале своего стиха, поэтому список
// заголовков — подряд идущие заголовки каждого стиха по порядку стихов.
// Если между первым стихом и повтором ни у одного стиха заголовков нет,
// заголовки повтора от заголовков первого не отличить: они остаются над
// первым стихом.
_Skipped _skipped(UsfmBook usfm) {
  final repeated = Set<UsfmVerse>.identity();
  final outOfRange = Set<UsfmVerse>.identity();
  final headings = Set<UsfmHeading>.identity();
  final notes = <int>{};
  final seen = <(int, int)>{};
  var next = 0;
  for (final verse in usfm.verses) {
    final key = (verse.chapter, verse.verse);
    final repeat = !seen.add(key);
    final beyond =
        verse.chapter > maxChapterNumber || verse.verse > maxVerseNumber;
    while (next < usfm.headings.length &&
        (usfm.headings[next].chapter, usfm.headings[next].verse) == key) {
      if (repeat || beyond) {
        headings.add(usfm.headings[next]);
        _collectNotes(usfm.headings[next].nodes, notes);
      }
      next++;
    }
    if (beyond) {
      outOfRange.add(verse);
    } else if (repeat) {
      repeated.add(verse);
    }
    if (repeat || beyond) {
      _collectNotes(verse.nodes, notes);
    }
  }

  return (
    repeated: repeated,
    outOfRange: outOfRange,
    headings: headings,
    notes: notes,
  );
}

// Добавляет в [ids] номера сносок [nodes].
void _collectNotes(List<MarkupNode> nodes, Set<int> ids) {
  for (final node in nodes) {
    switch (node) {
      case FootnoteRef(:final id):
        ids.add(id);
      case StyledSpan(:final children) ||
          TaggedWord(:final children) ||
          CrossrefLink(:final children):
        _collectNotes(children, ids);
      case TextRun() || LineBreak() || ParagraphBreak():
        break;
    }
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
        CrossrefLink(:final target, :final children) => CrossrefLink(
          target,
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

// Последний из слитых стихов каждого стиха книги по правилу FORMAT.md:
// `verse_end`, который заходит на следующий по номеру стих главы или больше
// своего стиха больше чем на [maxVerseEndSpan], отбрасывается, и стих
// пишется одним; это попадает в [warnings].
Map<UsfmVerse, int?> _verseEnds(UsfmBook usfm, List<String> warnings) {
  final numbers = <int, List<int>>{};
  for (final verse in usfm.verses) {
    numbers.putIfAbsent(verse.chapter, () => []).add(verse.verse);
  }
  for (final list in numbers.values) {
    list.sort();
  }
  final ends = Map<UsfmVerse, int?>.identity();
  for (final verse in usfm.verses) {
    final end = verse.verseEnd;
    if (end == null || end <= verse.verse) {
      ends[verse] = null;
      continue;
    }
    final place = '${usfm.code} ${verse.chapter}:${verse.verse}-$end';
    final next = numbers[verse.chapter]!.firstWhere(
      (number) => number > verse.verse,
      orElse: () => 0,
    );
    if (next > 0 && end >= next) {
      warnings.add('$place: reaches verse $next, written as one verse');
      ends[verse] = null;
    } else if (end - verse.verse > maxVerseEndSpan) {
      warnings.add(
        '$place: more than $maxVerseEndSpan verses, written as one verse',
      );
      ends[verse] = null;
    } else {
      ends[verse] = end;
    }
  }

  return ends;
}

// Глава → последний стих; у слитых стихов — последний из них по [ends].
// Стихи из [outOfRange] не считаются.
Map<int, int> _lastVerses(
  UsfmBook usfm,
  Map<UsfmVerse, int?> ends,
  Set<UsfmVerse> outOfRange,
) {
  final lasts = <int, int>{};
  for (final verse in usfm.verses) {
    if (outOfRange.contains(verse)) {
      continue;
    }
    final last = ends[verse] ?? verse.verse;
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

void _delete(File file) {
  if (file.existsSync()) {
    file.deleteSync();
  }
}
