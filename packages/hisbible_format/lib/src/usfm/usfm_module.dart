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
    this.movedVerses = 0,
    this.preface = const [],
    this.prefaceNotes = const [],
  });

  /// Предисловие модуля: части вступления файла `\id FRT` (вводные
  /// страницы издания); нет файла — пусто.
  final List<UsfmIntro> preface;

  /// Сноски предисловия: на них ссылаются знаки сносок в [preface].
  final List<UsfmNote> prefaceNotes;

  /// Книги в порядке чтения; [ordered] ставит их в порядок модуля.
  final List<UsfmBookEntry> books;

  /// Стихи, которые `translations.csv` считает, а в модуль они не идут:
  /// книг вне справочника и греческого Даниила, который повторяет `DAN`.
  final int skippedVerses;

  /// Стихи, которые `translations.csv` считает неканоническими, а модуль
  /// держит в Ветхом Завете: греческий Даниил на месте Даниила и 151-й
  /// псалом.
  final int movedVerses;

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
    movedVerses: movedVerses,
    warnings: warnings,
    preface: preface,
    prefaceNotes: prefaceNotes,
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
/// [UsfmBooks.warnings]. Файл `\id FRT` (вводные страницы издания) — не
/// книга: его вступление и сноски становятся [UsfmBooks.preface]
/// и [UsfmBooks.prefaceNotes], а стихи в нём выбрасываются
/// с предупреждением. [onProgress] — доля прочитанных
/// файлов от 0 до 1.
///
/// Греческий Даниил (`DAG`) и 151-й псалом (`PS2`) своих книг
/// в справочнике не имеют (слово владельца 2026-11-23):
/// - `DAG` без `DAN` — Даниил модуля;
/// - `DAG` рядом с `DAN` даёт только дополнения, которых в модуле нет
///   отдельными книгами: 3:24–90 — Песнь трёх отроков 1:1–67, глава 13 —
///   Сусанна, глава 14 — Вил; прочее повторяет `DAN` и выбрасывается;
/// - `PS2` — псалом 151 Псалтири, если в ней его нет; из нескольких глав
///   `PS2` берётся первая.
/// Выброшенное из них считается в [UsfmBooks.skippedVerses], взятое
/// в Даниил и Псалтирь — в [UsfmBooks.movedVerses].
UsfmBooks readUsfmBooks(
  Iterable<UsfmSource> files, {
  void Function(double fraction)? onProgress,
}) {
  final sorted = files.toList()..sort((a, b) => a.name.compareTo(b.name));
  final warnings = <String>[];
  final books = <UsfmBookEntry>[];
  var skippedVerses = 0;
  final numbers = <int>{};
  List<UsfmIntro>? preface;
  var prefaceNotes = const <UsfmNote>[];
  final greek = <String, UsfmBook>{};
  for (final (index, file) in sorted.indexed) {
    final usfm = parseUsfm(decodeUsfm(file.bytes));
    final code = usfm.code;
    final number = BookCatalog.numberOfCode(code);
    final info = number == null ? null : BookCatalog.byNumber(number);
    if (code.isEmpty) {
      warnings.add('${file.name}: no \\id, skipped');
    } else if (code == prefaceBookCode) {
      if (preface != null) {
        warnings.add('$code: second copy in ${file.name}, skipped');
      } else {
        // Строк заглавия у предисловия нет: `\mt` в `FRT` — заглавие
        // всего издания, его, как и прежде, не переносим.
        preface = [
          for (final part in usfm.intros)
            if (part.kind != IntroKind.bookTitle &&
                part.kind != IntroKind.bookSubtitle)
              part,
        ];
        prefaceNotes = usfm.notes;
        if (usfm.verses.isNotEmpty) {
          warnings.add('$code: verses dropped: ${usfm.verses.length}');
        }
      }
    } else if ((code == _greekDaniel || code == _psalm151) &&
        usfm.verses.isNotEmpty) {
      if (greek.containsKey(code)) {
        warnings.add('$code: second copy in ${file.name}, skipped');
      } else {
        greek[code] = usfm;
        _noteProblems(usfm, warnings);
      }
    } else if (number == null || info == null) {
      warnings.add('$code: not in the book catalog, skipped');
      skippedVerses += usfm.verses.length;
    } else if (usfm.verses.isEmpty) {
      warnings.add('$code: no verses in ${file.name}, skipped');
    } else if (!numbers.add(number)) {
      warnings.add('$code: second copy in ${file.name}, skipped');
    } else {
      books.add((number: number, info: info, usfm: usfm));
      _noteProblems(usfm, warnings);
    }
    onProgress?.call((index + 1) / sorted.length);
  }
  final daniel = _addGreekDaniel(greek[_greekDaniel], books, numbers, warnings);
  final psalm = _addPsalm151(greek[_psalm151], books, warnings);

  return UsfmBooks(
    books: books,
    skippedVerses: skippedVerses + daniel.skipped + psalm.skipped,
    movedVerses: daniel.moved + psalm.moved,
    warnings: warnings,
    preface: preface ?? const [],
    prefaceNotes: prefaceNotes,
  );
}

// Коды USFM греческого Даниила и 151-го псалма: книг справочника у них нет,
// их текст [readUsfmBooks] раскладывает по другим книгам.
const _greekDaniel = 'DAG';
const _psalm151 = 'PS2';

// Что из греческого Даниила берётся отдельными книгами, когда в модуле
// есть `DAN`: код книги, глава `DAG`, первый и последний стих.
const _danielAdditions = [
  ('S3Y', 3, 24, 90),
  ('SUS', 13, 1, maxVerseNumber),
  ('BEL', 14, 1, maxVerseNumber),
];

// Предупреждения о прочитанной книге [usfm]: `\periph` вне `FRT`,
// выброшенные куски и незнакомые маркеры.
void _noteProblems(UsfmBook usfm, List<String> warnings) {
  final code = usfm.code;
  final articles = usfm.intros
      .where((part) => part.kind == IntroKind.article)
      .length;
  if (articles > 0) {
    warnings.add('$code: \\periph outside FRT, read as a title: $articles');
  }
  if (usfm.droppedFragments > 0) {
    warnings.add('$code: dropped fragments: ${usfm.droppedFragments}');
  }
  if (usfm.unknownMarkers.isNotEmpty) {
    final markers = usfm.unknownMarkers.toList()..sort();
    warnings.add('$code: unknown markers: ${markers.join(', ')}');
  }
}

UsfmBookEntry _entry(UsfmBook usfm) {
  final number = BookCatalog.numberOfCode(usfm.code)!;

  return (number: number, info: BookCatalog.byNumber(number)!, usfm: usfm);
}

// Сколько кусков книги выброшено и сколько взято в Ветхий Завет.
typedef _Taken = ({int skipped, int moved});

// Кладёт греческого Даниила [dag] в [books] (см. [readUsfmBooks]).
_Taken _addGreekDaniel(
  UsfmBook? dag,
  List<UsfmBookEntry> books,
  Set<int> numbers,
  List<String> warnings,
) {
  if (dag == null) {
    return (skipped: 0, moved: 0);
  }
  final daniel = BookCatalog.numberOfCode('DAN')!;
  if (numbers.add(daniel)) {
    books.add(_entry(_copy(dag, code: 'DAN')));
    warnings.add('DAG: read as DAN');

    return (skipped: 0, moved: dag.verses.length);
  }
  var taken = 0;
  for (final (code, chapter, from, to) in _danielAdditions) {
    final slice = _slice(
      dag,
      code,
      chapter: chapter,
      from: from,
      to: to,
      shift: from - 1,
    );
    if (slice.verses.isEmpty) {
      continue;
    }
    if (!numbers.add(BookCatalog.numberOfCode(code)!)) {
      warnings.add('DAG: $code is already there, chapter $chapter skipped');
      continue;
    }
    books.add(_entry(slice));
    taken += slice.verses.length;
    warnings.add('DAG: chapter $chapter read as $code');
  }
  final rest = dag.verses.length - taken;
  if (rest > 0) {
    warnings.add('DAG: repeats DAN, verses dropped: $rest');
  }

  return (skipped: rest, moved: 0);
}

// Дописывает 151-й псалом [ps2] к Псалтири [books] (см. [readUsfmBooks]).
_Taken _addPsalm151(
  UsfmBook? ps2,
  List<UsfmBookEntry> books,
  List<String> warnings,
) {
  if (ps2 == null) {
    return (skipped: 0, moved: 0);
  }
  final psalms = BookCatalog.numberOfCode('PSA')!;
  final index = books.indexWhere((book) => book.number == psalms);
  final psa = index < 0 ? null : books[index].usfm;
  if (psa == null) {
    warnings.add('PS2: no PSA, skipped');

    return (skipped: ps2.verses.length, moved: 0);
  }
  if (psa.verses.any((verse) => verse.chapter == 151)) {
    warnings.add('PS2: PSA 151 is already there, skipped');

    return (skipped: ps2.verses.length, moved: 0);
  }
  final first = ps2.verses.first.chapter;
  var lastNote = 0;
  for (final note in psa.notes) {
    lastNote = note.id > lastNote ? note.id : lastNote;
  }
  final psalm = _slice(
    ps2,
    'PSA',
    chapter: first,
    from: 0,
    to: maxVerseNumber,
    shift: 0,
    newChapter: 151,
    noteShift: lastNote,
  );
  books[index] = _entry(
    _copy(
      psa,
      verses: [...psa.verses, ...psalm.verses],
      headings: [...psa.headings, ...psalm.headings],
      notes: [...psa.notes, ...psalm.notes],
    ),
  );
  warnings.add('PS2: read as PSA 151');
  final rest = ps2.verses.length - psalm.verses.length;
  if (rest > 0) {
    warnings.add('PS2: chapters after $first skipped');
  }

  return (skipped: rest, moved: psalm.verses.length);
}

// Книга [book] с другим кодом или с другими кусками, заголовками
// и сносками.
UsfmBook _copy(
  UsfmBook book, {
  String? code,
  List<UsfmVerse>? verses,
  List<UsfmHeading>? headings,
  List<UsfmNote>? notes,
}) => UsfmBook(
  code: code ?? book.code,
  intros: book.intros,
  verses: verses ?? book.verses,
  headings: headings ?? book.headings,
  notes: notes ?? book.notes,
  droppedFragments: book.droppedFragments,
  unknownMarkers: book.unknownMarkers,
  header: book.header,
  toc1: book.toc1,
  toc2: book.toc2,
  toc3: book.toc3,
  chapterLabel: book.chapterLabel,
);

// Стихи [from]–[to] главы [chapter] книги [book] с её заголовками
// и сносками — книгой [code] в одну главу [newChapter]: номера стихов
// меньше на [shift], номера сносок больше на [noteShift]. Названий
// и вступления у неё нет.
UsfmBook _slice(
  UsfmBook book,
  String code, {
  required int chapter,
  required int from,
  required int to,
  required int shift,
  int newChapter = 1,
  int noteShift = 0,
}) {
  bool inside(int c, int v) => c == chapter && v >= from && v <= to;

  return UsfmBook(
    code: code,
    intros: const [],
    verses: [
      for (final verse in book.verses)
        if (inside(verse.chapter, verse.verse))
          UsfmVerse(
            chapter: newChapter,
            verse: verse.verse - shift,
            nodes: _shiftNotes(verse.nodes, noteShift),
            verseEnd: verse.verseEnd == null ? null : verse.verseEnd! - shift,
            part: verse.part,
            partEnd: verse.partEnd,
            label: verse.label,
            number: verse.number,
          ),
    ],
    headings: [
      for (final heading in book.headings)
        if (inside(heading.chapter, heading.verse))
          UsfmHeading(
            chapter: newChapter,
            verse: heading.verse - shift,
            kind: heading.kind,
            level: heading.level,
            nodes: _shiftNotes(heading.nodes, noteShift),
            part: heading.part,
          ),
    ],
    notes: [
      for (final note in book.notes)
        if (inside(note.chapter, note.verse))
          UsfmNote(
            id: note.id + noteShift,
            chapter: newChapter,
            verse: note.verse - shift,
            kind: note.kind,
            caller: note.caller,
            nodes: _shiftNotes(note.nodes, noteShift),
          ),
    ],
    droppedFragments: 0,
    unknownMarkers: const {},
  );
}

/// Пишет модуль [path] с описанием [meta] из [books]: порядок книг — русский
/// для `ru`, `uk`, `be` из `meta.language`, иначе по номерам. Каждый `\v`
/// — свой кусок, на своём месте главы (такой же `\v` подряд разбор
/// дописывает к куску); повторные куски (тот же стих с той же частью, что
/// у куска раньше в главе) и куски с номерами вне границ формата
/// пропускаются, а конец куска, который заходит на следующий по номерам
/// кусок, отбрасывается; всё это попадает в `books.warnings`. Возвращает
/// счётчики ссылок из `\xt`. [onProgress] — доля записанных книг.
///
/// Схему нумерации каждой книги запись распознаёт по последним стихам глав
/// (`Versification.detect`); [schemes] — книги, чью схему задали руками:
/// номер книги → схема. Схема из [schemes] побеждает распознанную.
///
/// Файл `.part` и проверку модуля вызывающий ведёт сам. При ошибке бросает,
/// файл уже закрыт через [ModuleWriter.abort].
XtStats writeUsfmModule(
  String path,
  ModuleMeta meta,
  UsfmBooks books, {
  Map<int, VerseScheme> schemes = const {},
  void Function(double fraction)? onProgress,
}) {
  final language = meta.language;

  return _write(
    path,
    meta,
    books.ordered(language).books,
    books.preface,
    books.prefaceNotes,
    books.warnings,
    russian: _russianOrderLanguages.contains(language),
    language: language,
    schemes: schemes,
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

// Пишет модуль [path]; повторные куски и куски с номерами вне границ
// формата пропускаются и попадают в [warnings]. Возвращает счётчики
// ссылок из `\xt`.
XtStats _write(
  String path,
  ModuleMeta meta,
  List<UsfmBookEntry> books,
  List<UsfmIntro> preface,
  List<UsfmNote> prefaceNotes,
  List<String> warnings, {
  required bool russian,
  required String language,
  required Map<int, VerseScheme> schemes,
  void Function(double fraction)? onProgress,
}) {
  final skipped = {for (final book in books) book.number: _skipped(book.usfm)};
  final ends = {
    for (final book in books)
      book.number: _verseEnds(book.usfm, skipped[book.number]!, warnings),
  };
  final detected = Versification.standard.detect(
    {
      for (final book in books)
        book.number: _lastVerses(
          book.usfm,
          ends[book.number]!,
          skipped[book.number]!.outOfRange,
        ),
    },
    russianFlag: russian,
    preferred: Versification.hintsOf(language).preferred,
  );
  final forced = {
    for (final MapEntry(key: book, value: scheme) in schemes.entries)
      if (detected.schemes.containsKey(book)) book: scheme,
  };
  final bookSchemes = forced.isEmpty
      ? detected
      : BookSchemes(
          schemes: Map.unmodifiable({...detected.schemes, ...forced}),
          uncertain: Set.unmodifiable(
            detected.uncertain.difference(forced.keys.toSet()),
          ),
          manasseh: detected.manasseh,
        );
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
        bookSchemes.of(book.number),
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
    for (final part in preface) {
      writer.addPreface(part.kind, writeMarkup(part.nodes));
    }
    // Сноски предисловия — первыми, со своими номерами; номера сносок книг
    // идут после них.
    var noteOffset = 0;
    for (final note in prefaceNotes) {
      writer.addPrefaceFootnote(
        note.id,
        note.kind,
        note.caller,
        writeMarkup(note.nodes),
      );
      noteOffset = note.id > noteOffset ? note.id : noteOffset;
    }
    for (final (index, book) in books.indexed) {
      final usfm = book.usfm;
      writer.addBook(
        number: book.number,
        shortName: _shortName(book, language),
        longName: _longName(book),
        title: _filled(usfm.toc1),
        scheme: bookSchemes.of(book.number),
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

// Пишет куски, заголовки и сноски книги; конец куска (последний стих
// и его часть) — из [ends], номера сносок сдвинуты на [offset]. Куски
// из [skipped] пропускаются вместе со своими заголовками и сносками. Места
// из `\xt` сносок разбираются по названиям [names] и проверяются [exists];
// счётчики идут в [xt].
void _writeText(
  ModuleWriter writer,
  UsfmBookEntry book,
  Map<UsfmVerse, _End?> ends,
  _Skipped skipped,
  int offset,
  List<String> warnings, {
  required RefBooks names,
  required bool Function(RefRange place) exists,
  required XtStats xt,
}) {
  final UsfmBookEntry(:number, :usfm) = book;
  for (final verse in usfm.verses) {
    final place = '${usfm.code} ${verse.chapter}:${verse.verse}${verse.part}';
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
  for (final intro in usfm.intros) {
    // Статьи бывают только в предисловии модуля; в книге `\periph` —
    // заглавие вступления (предупреждение пишет [readUsfmBooks]), а автор
    // из его атрибута не нужен.
    if (intro.kind == IntroKind.author) {
      continue;
    }
    writer.addIntro(
      number,
      intro.kind == IntroKind.article ? IntroKind.title : intro.kind,
      writeMarkup(_shiftNotes(intro.nodes, offset)),
    );
  }
  for (final verse in usfm.verses) {
    if (skipped.repeated.contains(verse) ||
        skipped.outOfRange.contains(verse)) {
      continue;
    }
    final end = ends[verse];
    writer.addVerse(
      number,
      verse.chapter,
      verse.verse,
      writeMarkup(_shiftNotes(verse.nodes, offset)),
      verseEnd: end?.verse,
      part: verse.part,
      partEnd: end?.part ?? '',
    );
    if (verse.label case final label?) {
      writer.addVerseLabel(
        number,
        verse.chapter,
        verse.verse,
        label,
        part: verse.part,
      );
    }
    if (verse.number case final printed?) {
      writer.addVerseNumber(
        number,
        verse.chapter,
        verse.verse,
        printed,
        part: verse.part,
      );
    }
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
      // Места в заголовке — строка параллельных мест `\r` или `\xt`
      // в заголовке — становятся ссылками, как в сносках.
      writeMarkup(
        _shiftNotes(
          resolveXtLinks(
            heading.nodes,
            names,
            book: number,
            chapter: heading.chapter,
            exists: exists,
            stats: xt,
          ),
          offset,
        ),
      ),
      part: heading.part,
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

// Пропускаемые куски книги: повторные (та же глава, стих и часть, что
// у куска раньше) и с номерами вне границ формата (глава больше
// [maxChapterNumber] или стих больше [maxVerseNumber]); с их заголовками
// и сносками. Куски с разным началом друг друга не повторяют: где конец
// одного заходит на другой, [_verseEnds] отбрасывает конец.
//
// Разбор добавляет заголовки в начале своего куска, поэтому список
// заголовков — подряд идущие заголовки каждого куска по порядку кусков.
// Если между первым куском и повтором ни у одного куска заголовков нет,
// заголовки повтора от заголовков первого не отличить: они остаются над
// первым куском.
_Skipped _skipped(UsfmBook usfm) {
  final repeated = Set<UsfmVerse>.identity();
  final outOfRange = Set<UsfmVerse>.identity();
  final headings = Set<UsfmHeading>.identity();
  final notes = <int>{};
  final seen = <(int, int, String)>{};
  var next = 0;
  for (final verse in usfm.verses) {
    final key = (verse.chapter, verse.verse, verse.part);
    final repeat = !seen.add(key);
    final beyond =
        verse.chapter > maxChapterNumber || verse.verse > maxVerseNumber;
    while (next < usfm.headings.length &&
        (
              usfm.headings[next].chapter,
              usfm.headings[next].verse,
              usfm.headings[next].part,
            ) ==
            key) {
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
      case TextRun() ||
          LineBreak() ||
          ParagraphBreak() ||
          TableRow() ||
          TableCell():
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
        TextRun() ||
        LineBreak() ||
        ParagraphBreak() ||
        TableRow() ||
        TableCell() => node,
      },
  ];
}

// Конец куска: последний стих и его часть.
typedef _End = ({int verse, String part});

// Конец каждого куска книги по правилу FORMAT.md: куски главы идут по
// началам (стих, часть), пустая часть раньше любой буквы, и конец куска
// стоит строго раньше начала следующего. Конец, который заходит на начало
// следующего куска или уходит от своего стиха дальше [maxVerseEndSpan],
// отбрасывается вместе с частью, и кусок пишется в одном стихе; это
// попадает в [warnings]. Куски из [skipped] не пишутся и концы не режут.
Map<UsfmVerse, _End?> _verseEnds(
  UsfmBook usfm,
  _Skipped skipped,
  List<String> warnings,
) {
  bool kept(UsfmVerse verse) =>
      !skipped.repeated.contains(verse) && !skipped.outOfRange.contains(verse);
  final starts = <int, List<_End>>{};
  for (final verse in usfm.verses.where(kept)) {
    starts.putIfAbsent(verse.chapter, () => []).add((
      verse: verse.verse,
      part: verse.part,
    ));
  }
  for (final list in starts.values) {
    list.sort(_compareEnds);
  }
  final ends = Map<UsfmVerse, _End?>.identity();
  for (final verse in usfm.verses) {
    final last = verse.verseEnd;
    if (last == null || last <= verse.verse || !kept(verse)) {
      ends[verse] = null;
      continue;
    }
    final end = (verse: last, part: verse.partEnd);
    final start = (verse: verse.verse, part: verse.part);
    final place =
        '${usfm.code} ${verse.chapter}:${_pieceNumber(start)}'
        '-${_pieceNumber(end)}';
    final next = starts[verse.chapter]!
        .where((other) => _compareEnds(other, start) > 0)
        .firstOrNull;
    if (next != null && _compareEnds(end, next) >= 0) {
      warnings.add(
        '$place: reaches verse ${_pieceNumber(next)}, written as one verse',
      );
      ends[verse] = null;
    } else if (last - verse.verse > maxVerseEndSpan) {
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

// Порядок концов и начал кусков: по стиху, затем по части; пустая часть
// раньше любой буквы.
int _compareEnds(_End a, _End b) {
  final byVerse = a.verse.compareTo(b.verse);

  return byVerse != 0 ? byVerse : a.part.compareTo(b.part);
}

// Номер стиха с частью: `6`, `6b`.
String _pieceNumber(_End end) => '${end.verse}${end.part}';

// Глава → наибольший последний стих её кусков; у куска с концом — стих
// этого конца из [ends]. Куски из [outOfRange] не считаются.
Map<int, int> _lastVerses(
  UsfmBook usfm,
  Map<UsfmVerse, _End?> ends,
  Set<UsfmVerse> outOfRange,
) {
  final lasts = <int, int>{};
  for (final verse in usfm.verses) {
    if (outOfRange.contains(verse)) {
      continue;
    }
    final last = ends[verse]?.verse ?? verse.verse;
    if (last > (lasts[verse.chapter] ?? 0)) {
      lasts[verse.chapter] = last;
    }
  }

  return lasts;
}
