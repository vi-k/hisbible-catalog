// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/module_check.dart';
import 'package:hisbible_format/src/module/module_meta.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/problems.dart';
import 'package:sqlite3/sqlite3.dart';

/// Толкование к месту Писания.
final class Comment {
  /// Создаёт толкование.
  const Comment({
    required this.id,
    required this.book,
    required this.chapter,
    required this.verse,
    this.chapterEnd,
    this.verseEnd,
    required this.html,
  });

  /// Номер толкования в файле.
  final int id;

  /// Номер книги справочника.
  final int book;

  /// Глава, с которой начинается место.
  final int chapter;

  /// Стих, с которого начинается место.
  final int verse;

  /// Глава, на которой место кончается; `null` — та же глава.
  final int? chapterEnd;

  /// Последний стих места; `null` — один стих.
  final int? verseEnd;

  /// Текст толкования: HTML как у источника, ссылки `ref:` и `strong:`.
  final String html;

  @override
  bool operator ==(Object other) =>
      other is Comment &&
      other.id == id &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.chapterEnd == chapterEnd &&
      other.verseEnd == verseEnd &&
      other.html == html;

  @override
  int get hashCode =>
      Object.hash(id, book, chapter, verse, chapterEnd, verseEnd, html);

  @override
  String toString() =>
      'Comment($id, $book $chapter:$verse'
      '${chapterEnd == null ? '' : '-$chapterEnd'}'
      '${verseEnd == null ? '' : ':$verseEnd'}, $html)';
}

/// Открытый модуль толкований формата HisBible; файл читается только на
/// чтение.
final class CommentaryModule {
  CommentaryModule._(this._db, this.meta);

  /// Открывает толкования; негодный файл — [ModuleOpenException] с причиной.
  ///
  /// Модуль другого типа — [UnsupportedType]. Открытый модуль закрывают
  /// через [close].
  // Статический метод, а не конструктор: открытие читает файл.
  // ignore: prefer_constructors_over_static_methods
  static CommentaryModule open(String path) {
    final (db, meta) = openTypedModule(path, ModuleType.commentaries);

    return CommentaryModule._(db, meta);
  }

  final Database _db;
  bool _closed = false;

  /// Описание модуля из `meta`.
  final ModuleMeta meta;

  /// Толкования, которые начинаются в главе, по стихам и номерам.
  ///
  /// Толкование с незнакомой книгой не читается. Толкование, которое кончается
  /// в другой главе, лежит у главы начала.
  List<Comment> comments(int book, int chapter) {
    final code = BookCatalog.codeOf(book);

    return [
      for (final row in _db.select(
        'SELECT id, verse, chapter_end, verse_end, text FROM comments '
        'WHERE book = ? AND chapter = ? ORDER BY verse, id',
        [code, chapter],
      ))
        if ((
              row.columnAt(0),
              row.columnAt(1),
              row.columnAt(2),
              row.columnAt(3),
              row.columnAt(4),
            )
            case (
              final int id,
              final int verse,
              final Object? chapterEnd,
              final Object? verseEnd,
              final String html,
            ))
          Comment(
            id: id,
            book: book,
            chapter: chapter,
            verse: verse,
            chapterEnd: chapterEnd is int ? chapterEnd : null,
            verseEnd: verseEnd is int ? verseEnd : null,
            html: html,
          ),
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
}
