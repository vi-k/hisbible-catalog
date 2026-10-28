// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/module_check.dart';
import 'package:hisbible_format/src/module/module_meta.dart';
import 'package:hisbible_format/src/module/schema.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/problems.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';
import 'package:sqlite3/sqlite3.dart';

/// Книга перевода, у которой есть стихи.
final class ModuleBook {
  /// Создаёт описание книги.
  const ModuleBook({
    required this.number,
    required this.code,
    required this.shortName,
    required this.longName,
    required this.title,
    required this.chapters,
    required this.kind,
    required this.scheme,
  });

  /// Номер книги справочника.
  final int number;

  /// Код книги в файле: SIL или `H<номер>`.
  final String code;

  /// Короткое название из модуля.
  final String shortName;

  /// Полное название из модуля.
  final String longName;

  /// Полное заглавие книги; `null`, если его нет.
  final String? title;

  /// Номера глав со стихами по возрастанию.
  final List<int> chapters;

  /// Книга справочника или нет.
  final BookKind kind;

  /// Схема нумерации стихов книги.
  final VerseScheme scheme;
}

/// Стих главы.
final class Verse {
  /// Создаёт стих; [verseEnd] — последний из слитых стихов.
  const Verse(this.verse, this.text, {this.verseEnd});

  /// Номер стиха; у слитых стихов — первый.
  final int verse;

  /// Текст стиха в разметке формата.
  final String text;

  /// Последний из слитых стихов; `null` — стих один.
  final int? verseEnd;

  @override
  bool operator ==(Object other) =>
      other is Verse &&
      other.verse == verse &&
      other.text == text &&
      other.verseEnd == verseEnd;

  @override
  int get hashCode => Object.hash(verse, text, verseEnd);

  @override
  String toString() =>
      'Verse($verse${verseEnd == null ? '' : '-$verseEnd'}, $text)';
}

/// Заголовок над стихом.
final class Heading {
  /// Создаёт заголовок.
  const Heading(this.verse, this.order, this.kind, this.level, this.text);

  /// Номер стиха, над которым стоит заголовок.
  final int verse;

  /// Порядок среди заголовков одного стиха, с 0.
  final int order;

  /// Вид заголовка.
  final HeadingKind kind;

  /// Уровень, 1..3.
  final int level;

  /// Текст заголовка в разметке формата.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Heading &&
      other.verse == verse &&
      other.order == order &&
      other.kind == kind &&
      other.level == level &&
      other.text == text;

  @override
  int get hashCode => Object.hash(verse, order, kind, level, text);

  @override
  String toString() => 'Heading($verse, $order, ${kind.name}, $level, $text)';
}

/// Сноска к стиху.
final class Footnote {
  /// Создаёт сноску.
  const Footnote(
    this.id,
    this.book,
    this.chapter,
    this.verse,
    this.kind,
    this.caller,
    this.text,
  );

  /// Номер сноски, на который ссылается `<f id>`.
  final int id;

  /// Номер книги справочника.
  final int book;

  /// Глава.
  final int chapter;

  /// Стих.
  final int verse;

  /// Вид сноски.
  final FootnoteKind kind;

  /// Знак сноски; пустой — без знака.
  final String caller;

  /// Текст сноски в разметке формата.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Footnote &&
      other.id == id &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.kind == kind &&
      other.caller == caller &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, book, chapter, verse, kind, caller, text);

  @override
  String toString() =>
      'Footnote($id, $book $chapter:$verse, ${kind.name}, $caller, $text)';
}

/// Открытый модуль Библии формата HisBible; файл читается только на чтение.
final class BibleModule {
  BibleModule._(
    this._db,
    this.meta,
    this.books,
    this._codes,
    this._lastVerses,
    this.hasParagraphMarks,
  ) : _byNumber = {for (final book in books) book.number: book};

  /// Открывает Библию; негодный файл — [ModuleOpenException] с причиной.
  ///
  /// Модуль другого типа — [UnsupportedType]. Открытый модуль закрывают
  /// через [close].
  static BibleModule open(String path) {
    final problem = checkModuleFile(path);
    if (problem != null) {
      throw ModuleOpenException(problem);
    }
    final db = openModuleReadOnly(path);
    var done = false;
    try {
      final meta = readCheckedMeta(db);
      if (meta.type != ModuleType.bible) {
        throw ModuleOpenException(UnsupportedType(typeValue(meta.type)));
      }
      final codes = readBookCodes(db);
      final lastVerses = _readLastVerses(db, codes);
      final module = BibleModule._(
        db,
        meta,
        _readBooks(db, codes, lastVerses),
        {for (final MapEntry(:key, :value) in codes.entries) value: key},
        lastVerses,
        readMetaValues(db)['paragraphs'] == '1',
      );
      done = true;

      return module;
    } on SqliteException catch (e) {
      throw ModuleOpenException(problemOfSqlite(e));
    } finally {
      if (!done) {
        db.close();
      }
    }
  }

  final Database _db;
  // Номер книги → код в файле.
  final Map<int, String> _codes;
  final Map<int, Map<int, int>> _lastVerses;
  final Map<int, ModuleBook> _byNumber;
  bool _closed = false;

  /// Описание модуля из `meta`.
  final ModuleMeta meta;

  /// Книги со стихами в порядке модуля (`books.position`).
  ///
  /// Книга с кодом, которого справочник не знает, и книга без стихов
  /// пропускаются.
  final List<ModuleBook> books;

  /// Книга по номеру справочника или `null`, если её в модуле нет.
  ModuleBook? book(int number) => _byNumber[number];

  /// Схемы нумерации книг из `books.scheme`; [BookSchemes.uncertain] пуст.
  BookSchemes get schemes => BookSchemes(
    schemes: {for (final book in books) book.number: book.scheme},
  );

  /// Есть ли в стихах `<p/>`: ключ `meta` `paragraphs` равен `1`.
  ///
  /// Модуль без `<p/>` показывает сплошной текст.
  final bool hasParagraphMarks;

  /// Книга → глава → последний стих; у слитых стихов — по `verse_end`.
  Map<int, Map<int, int>> lastVerses() => {
    for (final MapEntry(:key, :value) in _lastVerses.entries)
      key: Map<int, int>.of(value),
  };

  /// Стихи главы по возрастанию номеров.
  ///
  /// `verse_end`, который не больше `verse`, больше его больше чем на
  /// [maxVerseEndSpan] или заходит на следующий стих главы, читается как
  /// `null`: стих один.
  List<Verse> chapter(int book, int chapter) {
    final code = _codes[book];
    if (code == null) {
      return const [];
    }
    final rows = _db.select(
      'SELECT verse, verse_end, text FROM verses '
      'WHERE book = ? AND chapter = ? AND verse >= 1 ORDER BY verse',
      [code, chapter],
    );

    return [
      for (var i = 0; i < rows.length; i++)
        if ((rows[i].columnAt(0), rows[i].columnAt(2)) case (
          final int verse,
          final String text,
        ))
          Verse(
            verse,
            text,
            verseEnd: _verseEnd(
              verse,
              rows[i].columnAt(1),
              i + 1 < rows.length ? rows[i + 1].columnAt(0) : null,
            ),
          ),
    ];
  }

  /// Заголовки главы по стихам и порядку; незнакомый вид пропускается.
  List<Heading> headings(int book, int chapter) {
    final code = _codes[book];
    if (code == null) {
      return const [];
    }

    return [
      for (final row in _db.select(
        'SELECT verse, position, kind, level, text FROM headings '
        'WHERE book = ? AND chapter = ? ORDER BY verse, position',
        [code, chapter],
      ))
        if ((
              row.columnAt(0),
              row.columnAt(1),
              headingKindOfValue(row.columnAt(2)),
              row.columnAt(3),
              row.columnAt(4),
            )
            case (
              final int verse,
              final int order,
              final HeadingKind kind,
              final int level,
              final String text,
            ))
          Heading(verse, order, kind, level, text),
    ];
  }

  /// Сноски главы по стихам и номерам; незнакомый вид пропускается.
  List<Footnote> footnotes(int book, int chapter) {
    final code = _codes[book];
    if (code == null) {
      return const [];
    }

    return [
      for (final row in _db.select(
        'SELECT id, verse, kind, caller, text FROM footnotes '
        'WHERE book = ? AND chapter = ? ORDER BY verse, id',
        [code, chapter],
      ))
        if ((
              row.columnAt(0),
              row.columnAt(1),
              footnoteKindOfValue(row.columnAt(2)),
              row.columnAt(3),
              row.columnAt(4),
            )
            case (
              final int id,
              final int verse,
              final FootnoteKind kind,
              final String caller,
              final String text,
            ))
          Footnote(id, book, chapter, verse, kind, caller, text),
    ];
  }

  /// Закрывает базу; повторный вызов ничего не делает.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _db.close();
  }

  // Последний из слитых стихов [value] стиха [verse], за которым в главе идёт
  // стих [next]; `null`, если [value] не больше [verse], больше его больше
  // чем на [maxVerseEndSpan] или не меньше [next]. Это же правило —
  // в запросе [_readLastVerses].
  static int? _verseEnd(int verse, Object? value, Object? next) =>
      value is int &&
          value > verse &&
          value - verse <= maxVerseEndSpan &&
          (next is! int || value < next)
      ? value
      : null;

  // Книга → глава → последний стих, только у книг из [codes]; `verse_end`
  // берётся по правилу [_verseEnd].
  static Map<int, Map<int, int>> _readLastVerses(
    Database db,
    Map<String, int> codes,
  ) {
    final lastVerses = <int, Map<int, int>>{};
    for (final row in db.select(
      'SELECT book, chapter, MAX(CASE '
      "WHEN typeof(verse_end) = 'integer' AND verse_end > verse "
      'AND verse_end - verse <= ? '
      "AND (typeof(next) != 'integer' OR verse_end < next) "
      'THEN verse_end ELSE verse END) '
      'FROM (SELECT book, chapter, verse, verse_end, '
      'LEAD(verse) OVER (PARTITION BY book, chapter ORDER BY verse) AS next '
      'FROM verses WHERE chapter >= 1 AND verse >= 1) '
      'GROUP BY book, chapter',
      [maxVerseEndSpan],
    )) {
      final number = codes[row.columnAt(0)];
      if ((number, row.columnAt(1), row.columnAt(2)) case (
        final int number,
        final int chapter,
        final int last,
      )) {
        lastVerses.putIfAbsent(number, () => {})[chapter] = last;
      }
    }

    return lastVerses;
  }

  static List<ModuleBook> _readBooks(
    Database db,
    Map<String, int> codes,
    Map<int, Map<int, int>> lastVerses,
  ) => [
    for (final row in db.select(
      'SELECT code, short_name, long_name, title, scheme FROM books '
      'ORDER BY position',
    ))
      if (_book(row, codes, lastVerses) case final ModuleBook book) book,
  ];

  static ModuleBook? _book(
    Row row,
    Map<String, int> codes,
    Map<int, Map<int, int>> lastVerses,
  ) {
    final code = row.columnAt(0);
    final number = codes[code];
    final chapters = number == null ? null : lastVerses[number];
    if (code is! String || number == null || chapters == null) {
      return null;
    }
    final info = BookCatalog.byNumber(number);
    final shortName = _text(row.columnAt(1)) ?? code;

    return ModuleBook(
      number: number,
      code: code,
      shortName: shortName,
      longName: _text(row.columnAt(2)) ?? shortName,
      title: _text(row.columnAt(3)),
      chapters: chapters.keys.toList()..sort(),
      kind: info == null
          ? BookKind.outsideTable
          : info.deuterocanonical
          ? BookKind.deuterocanonical
          : BookKind.canonical,
      scheme: schemeOfValue(row.columnAt(4)) ?? VerseScheme.eng,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();

    return text.isEmpty ? null : text;
  }
}
