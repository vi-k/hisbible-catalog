// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/module_check.dart';
import 'package:hisbible_format/src/module/module_meta.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/problems.dart';
import 'package:sqlite3/sqlite3.dart';

/// Перекрёстная ссылка от стиха (или стихов) к месту Писания.
final class CrossRef {
  /// Создаёт ссылку.
  const CrossRef({
    required this.book,
    required this.chapter,
    required this.verse,
    this.verseEnd,
    required this.toBook,
    required this.toChapter,
    required this.toVerse,
    this.toChapterEnd,
    this.toVerseEnd,
    this.votes = 0,
  });

  /// Номер книги справочника, от которой идёт ссылка.
  final int book;

  /// Глава, от которой идёт ссылка.
  final int chapter;

  /// Стих, от которого идёт ссылка.
  final int verse;

  /// Последний стих, от которого идёт ссылка; `null` — один стих.
  final int? verseEnd;

  /// Номер книги справочника, на которую ссылка указывает.
  final int toBook;

  /// Глава, на которую ссылка указывает.
  final int toChapter;

  /// Стих, на который ссылка указывает.
  final int toVerse;

  /// Глава, на которой место кончается; `null` — та же глава.
  final int? toChapterEnd;

  /// Последний стих места; `null` — один стих.
  final int? toVerseEnd;

  /// Вес ссылки у источника: чем больше, тем она уместнее.
  final int votes;

  @override
  bool operator ==(Object other) =>
      other is CrossRef &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.verseEnd == verseEnd &&
      other.toBook == toBook &&
      other.toChapter == toChapter &&
      other.toVerse == toVerse &&
      other.toChapterEnd == toChapterEnd &&
      other.toVerseEnd == toVerseEnd &&
      other.votes == votes;

  @override
  int get hashCode => Object.hash(
    book,
    chapter,
    verse,
    verseEnd,
    toBook,
    toChapter,
    toVerse,
    toChapterEnd,
    toVerseEnd,
    votes,
  );

  @override
  String toString() =>
      'CrossRef($book $chapter:$verse'
      '${verseEnd == null ? '' : '-$verseEnd'} -> '
      '$toBook $toChapter:$toVerse'
      '${toChapterEnd == null ? '' : '-$toChapterEnd'}'
      '${toVerseEnd == null ? '' : ':$toVerseEnd'}, votes $votes)';
}

/// Открытый модуль перекрёстных ссылок формата HisBible; файл читается только
/// на чтение.
final class CrossrefModule {
  CrossrefModule._(this._db, this.meta);

  /// Открывает ссылки; негодный файл — [ModuleOpenException] с причиной.
  ///
  /// Модуль другого типа — [UnsupportedType]. Открытый модуль закрывают
  /// через [close].
  // Статический метод, а не конструктор: открытие читает файл.
  // ignore: prefer_constructors_over_static_methods
  static CrossrefModule open(String path) {
    final (db, meta) = openTypedModule(path, ModuleType.crossReferences);

    return CrossrefModule._(db, meta);
  }

  final Database _db;
  bool _closed = false;

  /// Описание модуля из `meta`.
  final ModuleMeta meta;

  /// Ссылки от стихов главы по стихам, затем по убыванию веса.
  ///
  /// Ссылка на книгу, которой справочник не знает, не читается.
  List<CrossRef> from(int book, int chapter) {
    final code = BookCatalog.codeOf(book);
    final refs = <CrossRef>[];
    for (final row in _db.select(
      'SELECT verse, verse_end, to_book, to_chapter, to_verse, '
      'to_chapter_end, to_verse_end, votes FROM crossrefs '
      'WHERE book = ? AND chapter = ? ORDER BY verse, votes DESC, rowid',
      [code, chapter],
    )) {
      final toCode = row.columnAt(2);
      final toBook = toCode is String ? BookCatalog.numberOfCode(toCode) : null;
      if ((
            row.columnAt(0),
            toBook,
            row.columnAt(3),
            row.columnAt(4),
            row.columnAt(7),
          )
          case (
            final int verse,
            final int toBook,
            final int toChapter,
            final int toVerse,
            final int votes,
          )) {
        final verseEnd = row.columnAt(1);
        final toChapterEnd = row.columnAt(5);
        final toVerseEnd = row.columnAt(6);
        refs.add(
          CrossRef(
            book: book,
            chapter: chapter,
            verse: verse,
            verseEnd: verseEnd is int ? verseEnd : null,
            toBook: toBook,
            toChapter: toChapter,
            toVerse: toVerse,
            toChapterEnd: toChapterEnd is int ? toChapterEnd : null,
            toVerseEnd: toVerseEnd is int ? toVerseEnd : null,
            votes: votes,
          ),
        );
      }
    }

    return refs;
  }

  /// Закрывает базу; повторный вызов ничего не делает.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _db.close();
  }
}
