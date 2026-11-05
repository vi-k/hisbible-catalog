import 'dart:convert';

import 'package:hisbible_format/hisbible_format.dart';

/// Файл USFM: имя (для предупреждений) и байты.
typedef UsfmSource = ({String name, List<int> bytes});

/// Книга USFM с номером справочника.
typedef UsfmBookEntry = ({int number, BookInfo info, UsfmBook usfm});

/// Языки, у которых книги идут в порядке [BookCatalog.russianOrder].
const _russianOrderLanguages = {'ru', 'uk', 'be'};

// Длина выборки текста в знаках: вдвое больше 10 000 букв, которые считает
// определитель письменности, с запасом на пробелы, цифры и знаки.
const _sampleLength = 20000;

/// Текст файла USFM: BOM UTF-8, UTF-16 LE и BE по BOM; иначе UTF-8,
/// битые байты — U+FFFD. BOM в текст не входит.
String decodeUsfm(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, bigEndian: false);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, bigEndian: true);
  }
  final text = utf8.decode(bytes, allowMalformed: true);

  return text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF
      ? text.substring(1)
      : text;
}

// UTF-16 после двухбайтного BOM; непарный последний байт отбрасывается.
String _utf16(List<int> bytes, {required bool bigEndian}) {
  final units = <int>[
    for (var i = 2; i + 1 < bytes.length; i += 2)
      if (bigEndian)
        (bytes[i] << 8) | bytes[i + 1]
      else
        (bytes[i + 1] << 8) | bytes[i],
  ];

  return String.fromCharCodes(units);
}

/// Прочитанные книги: по номерам, без повторов; что пропущено — в [warnings].
final class UsfmBooks {
  /// Создаёт набор прочитанных книг.
  const UsfmBooks({
    required this.books,
    required this.skippedVerses,
    required this.warnings,
  });

  /// Книги в порядке чтения; [ordered] ставит их в порядок модуля.
  final List<UsfmBookEntry> books;

  /// Стихи книг вне справочника: `translations.csv` их считает, а в модуль
  /// они не идут.
  final int skippedVerses;

  /// Что пропущено или выброшено. [writeUsfmModule] дописывает сюда своё.
  final List<String> warnings;

  /// `\cl` первой книги, если он непустой.
  String? get chapterLabel => _filled(books.first.usfm.chapterLabel);

  /// Те же книги в порядке модуля языка [language]: русском для `ru`, `uk`
  /// и `be`, иначе по номерам; книги вне русского порядка идут после него,
  /// по номерам. Список [warnings] общий.
  UsfmBooks ordered(String language) => UsfmBooks(
    books: [...books]..sort(_orderOf(language)),
    skippedVerses: skippedVerses,
    warnings: warnings,
  );

  /// Начало текста книг для определения письменности: до 20 000 знаков.
  String sample() {
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
}

/// Разбирает [files] по порядку имён; книга без номера в справочнике,
/// без `\id`, без стихов или повторная пропускается и попадает в
/// [UsfmBooks.warnings]. [onProgress] — доля прочитанных файлов от 0 до 1.
UsfmBooks readUsfmBooks(
  Iterable<UsfmSource> files, {
  void Function(double fraction)? onProgress,
}) {
  final sorted = files.toList()..sort((a, b) => a.name.compareTo(b.name));
  final warnings = <String>[];
  final books = <UsfmBookEntry>[];
  var skippedVerses = 0;
  final numbers = <int>{};
  for (final (index, file) in sorted.indexed) {
    final usfm = parseUsfm(decodeUsfm(file.bytes));
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
    onProgress?.call((index + 1) / sorted.length);
  }

  return UsfmBooks(
    books: books,
    skippedVerses: skippedVerses,
    warnings: warnings,
  );
}

/// Пишет модуль [path] с описанием [meta] из [books]: порядок книг — русский
/// для `ru`, `uk`, `be` из `meta.language`, иначе по номерам; повторные
/// стихи и стихи с номерами вне границ формата пропускаются и попадают
/// в `books.warnings`. Возвращает счётчики ссылок из `\xt`. [onProgress] —
/// доля записанных книг.
///
/// Файл `.part` и проверку модуля вызывающий ведёт сам. При ошибке бросает,
/// файл уже закрыт через [ModuleWriter.abort].
XtStats writeUsfmModule(
  String path,
  ModuleMeta meta,
  UsfmBooks books, {
  void Function(double fraction)? onProgress,
}) {
  final language = meta.language;

  return _write(
    path,
    meta,
    books.ordered(language).books,
    books.warnings,
    russian: _russianOrderLanguages.contains(language),
    language: language,
    onProgress: onProgress,
  );
}

// Порядок книг: по номерам или, у русских языков, по русскому порядку; книги
// вне русского порядка — после него, по номерам.
int Function(UsfmBookEntry, UsfmBookEntry) _orderOf(String language) {
  final russian = _russianOrderLanguages.contains(language);
  int rank(UsfmBookEntry book) {
    if (!russian) {
      return book.number;
    }
    final index = BookCatalog.russianOrder.indexOf(book.number);

    return index < 0 ? BookCatalog.russianOrder.length + book.number : index;
  }

  return (a, b) => rank(a).compareTo(rank(b));
}

String? _filled(String? text) {
  final trimmed = text?.trim();

  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

// Короткое название книги: `\toc3`. У русского и английского перевода,
// где `\toc3` нет или в нём полное название (без учёта регистра), —
// сокращение справочника («Быт», «Gen»; решение владельца 2026-10-26).
String _shortName(UsfmBookEntry book, String language) {
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
  List<UsfmBookEntry> books,
  List<String> warnings, {
  required bool russian,
  required String language,
  void Function(double fraction)? onProgress,
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
    for (final (index, book) in books.indexed) {
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
      onProgress?.call((index + 1) / books.length);
    }
    writer.finish();
  } on Object {
    writer.abort();
    rethrow;
  }

  return xt;
}

// Полное название книги: `\toc2`, потом `\h`, `\toc1` и справочник.
String _longName(UsfmBookEntry book) =>
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
  UsfmBookEntry book,
  Map<UsfmVerse, int?> ends,
  _Skipped skipped,
  int offset,
  List<String> warnings, {
  required RefBooks names,
  required bool Function(RefRange place) exists,
  required XtStats xt,
}) {
  final UsfmBookEntry(:number, :usfm) = book;
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
