import 'dart:io';

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/bible_module.dart';
import 'package:hisbible_format/src/module/module_meta.dart';
import 'package:hisbible_format/src/module/schema.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';
import 'package:sqlite3/sqlite3.dart';

/// Пишет файл модуля HisBible.
///
/// Книги, стихи, заголовки и сноски добавляются в одной транзакции; файл
/// готов после [finish]. Номера книг — номера справочника, в файл идут их
/// коды ([BookCatalog.codeOf]). Ошибка записи — [SqliteException]; после
/// неё зовут [abort].
final class ModuleWriter {
  ModuleWriter._(this._path, this._db, this._type);

  /// Создаёт файл [path] с подписью формата, таблицами типа и [meta].
  ///
  /// Существующий файл заменяется.
  // Статический метод, а не конструктор: создание пишет файл.
  // ignore: prefer_constructors_over_static_methods
  static ModuleWriter create(String path, ModuleMeta meta) {
    _delete(path);
    final db = sqlite3.open(path);
    try {
      db
        ..execute('PRAGMA application_id = $formatApplicationId')
        ..execute('PRAGMA user_version = $formatVersion')
        ..execute('PRAGMA journal_mode = MEMORY')
        ..execute('BEGIN');
      for (final table in tablesOf(meta.type)) {
        db.execute(table.create);
      }
      final insert = db.prepare('INSERT INTO meta VALUES (?, ?)');
      try {
        for (final MapEntry(:key, :value) in meta.toValues().entries) {
          insert.execute([key, value]);
        }
      } finally {
        insert.close();
      }
    } on Object {
      db.close();
      _delete(path);
      rethrow;
    }

    return ModuleWriter._(path, db, meta.type);
  }

  final String _path;
  final Database _db;
  final ModuleType _type;
  final Map<String, PreparedStatement> _statements = {};
  // Следующий номер заголовка над каждым стихом.
  final Map<(String, int, int), int> _headingPositions = {};
  int _bookPosition = 0;
  bool _paragraphs = false;
  bool _closed = false;

  /// Добавляет книгу [number]; порядок книг — порядок вызовов.
  ///
  /// [color] — `0xRRGGBB`, `null` — цвет справочника.
  void addBook({
    required int number,
    required String shortName,
    required String longName,
    String? title,
    required VerseScheme scheme,
    int? color,
  }) {
    _bookPosition++;
    _statement('INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?)').execute([
      _bookPosition,
      BookCatalog.codeOf(number),
      shortName,
      longName,
      title,
      scheme.name,
      color,
    ]);
  }

  /// Добавляет стих в разметке формата; [verseEnd] — последний из слитых.
  void addVerse(
    int book,
    int chapter,
    int verse,
    String text, {
    int? verseEnd,
  }) {
    if (!_paragraphs && text.contains('<p/>')) {
      _paragraphs = true;
    }
    _statement('INSERT INTO verses VALUES (?, ?, ?, ?, ?)')
        .execute([BookCatalog.codeOf(book), chapter, verse, verseEnd, text]);
  }

  /// Добавляет заголовок над стихом; порядок над одним стихом — порядок
  /// вызовов.
  void addHeading(
    int book,
    int chapter,
    int verse,
    HeadingKind kind,
    int level,
    String text,
  ) {
    final code = BookCatalog.codeOf(book);
    final key = (code, chapter, verse);
    final position = _headingPositions[key] ?? 0;
    _headingPositions[key] = position + 1;
    _statement('INSERT INTO headings VALUES (?, ?, ?, ?, ?, ?, ?)')
        .execute([code, chapter, verse, position, kind.name, level, text]);
  }

  /// Добавляет сноску [id] к стиху; на неё ссылается `<f id>` в тексте.
  void addFootnote(
    int id,
    int book,
    int chapter,
    int verse,
    FootnoteKind kind,
    String caller,
    String text,
  ) {
    _statement('INSERT INTO footnotes VALUES (?, ?, ?, ?, ?, ?, ?)').execute(
      _footnoteRow(Footnote(id, book, chapter, verse, kind, caller, text)),
    );
  }

  /// Дописывает `paragraphs` в `meta`, строит индексы, сжимает и закрывает
  /// файл.
  void finish() {
    _checkOpen();
    try {
      if (_paragraphs) {
        _db.execute("INSERT INTO meta VALUES ('paragraphs', '1')");
      }
      for (final index in indexesOf(_type)) {
        _db.execute(index);
      }
      _closeStatements();
      _db
        ..execute('COMMIT')
        ..execute('VACUUM');
    } on Object {
      abort();
      rethrow;
    }
    _closed = true;
    _db.close();
  }

  /// Закрывает запись и удаляет файл; после [finish] ничего не делает.
  void abort() {
    if (_closed) {
      return;
    }
    _closed = true;
    _closeStatements();
    _db.close();
    _delete(_path);
  }

  PreparedStatement _statement(String sql) {
    _checkOpen();

    return _statements.putIfAbsent(sql, () => _db.prepare(sql));
  }

  void _closeStatements() {
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('ModuleWriter is closed');
    }
  }

  static void _delete(String path) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

/// Заменяет все сноски файла Библии [path] на [footnotes].
///
/// Нужна для копии модуля, ещё не поставленной на место: поставленный модуль
/// не меняется. Ошибка записи — [SqliteException], файл тогда прежний.
void replaceFootnotes(String path, List<Footnote> footnotes) {
  final db = sqlite3.open(path, mode: OpenMode.readWrite);
  try {
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM footnotes');
      final insert = db.prepare(
        'INSERT INTO footnotes VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final footnote in footnotes) {
          insert.execute(_footnoteRow(footnote));
        }
      } finally {
        insert.close();
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
    db.execute('VACUUM');
  } finally {
    db.close();
  }
}

// Строка таблицы footnotes для [footnote].
List<Object?> _footnoteRow(Footnote footnote) => [
  footnote.id,
  BookCatalog.codeOf(footnote.book),
  footnote.chapter,
  footnote.verse,
  footnote.kind.name,
  footnote.caller,
  footnote.text,
];
