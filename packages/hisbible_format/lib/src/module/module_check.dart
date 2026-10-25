import 'dart:io';

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/module_meta.dart';
import 'package:hisbible_format/src/module/schema.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/problems.dart';
import 'package:sqlite3/sqlite3.dart';

// Код SQLITE_NOTADB: файл не база SQLite.
const int _notADatabase = 26;

/// Проверяет файл модуля HisBible; `null` — модуль в порядке.
///
/// Проверяются подпись и версия формата, обязательные ключи `meta`, таблицы
/// типа модуля и их столбцы, а у Библии — хотя бы один стих книги из
/// `books`; у толкований и ссылок — хотя бы одна запись с известной книгой.
/// Исключений наружу не бросает: любой отказ — это [ModuleProblem].
ModuleProblem? checkModuleFile(String path) {
  final Database db;
  try {
    db = openModuleReadOnly(path);
  } on ModuleOpenException catch (e) {
    return e.problem;
  }
  try {
    final meta = readCheckedMeta(db);
    for (final table in tablesOf(meta.type).skip(1)) {
      final columns = _columnsOf(db, table.name);
      if (columns.isEmpty) {
        return MissingTable(table.name);
      }
      for (final column in table.columns) {
        if (!columns.contains(column)) {
          return MissingColumn(table.name, column);
        }
      }
    }
    if (!_hasReadableContent(db, meta.type)) {
      return const EmptyModule();
    }

    return null;
  } on ModuleOpenException catch (e) {
    return e.problem;
  } on SqliteException catch (e) {
    return problemOfSqlite(e);
  } finally {
    db.close();
  }
}

/// Открывает модуль типа [type] для чтения: файл проверен [checkModuleFile].
///
/// Негодный файл — [ModuleOpenException] с причиной, модуль другого типа —
/// с [UnsupportedType] (имя его типа). Базу закрывает вызвавший.
(Database, ModuleMeta) openTypedModule(String path, ModuleType type) {
  final problem = checkModuleFile(path);
  if (problem != null) {
    throw ModuleOpenException(problem);
  }
  final db = openModuleReadOnly(path);
  try {
    final meta = readCheckedMeta(db);
    if (meta.type != type) {
      throw ModuleOpenException(UnsupportedType(typeValue(meta.type)));
    }

    return (db, meta);
  } on SqliteException catch (e) {
    db.close();
    throw ModuleOpenException(problemOfSqlite(e));
  } on Object {
    db.close();
    rethrow;
  }
}

/// Читает `meta` модуля любого типа; негодный файл — [ModuleOpenException].
ModuleMeta readModuleMeta(String path) {
  final db = openModuleReadOnly(path);
  try {
    return readCheckedMeta(db);
  } on SqliteException catch (e) {
    throw ModuleOpenException(problemOfSqlite(e));
  } finally {
    db.close();
  }
}

/// Открывает файл только на чтение; негодный файл — [ModuleOpenException].
///
/// Подпись формата здесь не проверяется: это делает [readCheckedMeta].
Database openModuleReadOnly(String path) {
  if (!File(path).existsSync()) {
    throw ModuleOpenException(const Unreadable('file not found'));
  }
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
  } on SqliteException catch (e) {
    throw ModuleOpenException(problemOfSqlite(e));
  }
  try {
    // Заголовок файла проверяется на первом запросе, а не при открытии.
    db.select('SELECT 1 FROM sqlite_master LIMIT 1');
  } on SqliteException catch (e) {
    db.close();
    throw ModuleOpenException(problemOfSqlite(e));
  }

  return db;
}

/// Причина отказа по ошибке SQLite.
ModuleProblem problemOfSqlite(SqliteException e) =>
    e.resultCode == _notADatabase ? const NotSqlite() : Unreadable(e.message);

/// Проверяет подпись и версию формата и читает `meta` открытой базы.
///
/// Чужая база — [NotHisbibleModule], версия новее [formatVersion] —
/// [NewerFormat], без таблицы `meta` — [MissingTable]; всё это
/// в [ModuleOpenException].
ModuleMeta readCheckedMeta(Database db) {
  final applicationId = db.select('PRAGMA application_id').single.columnAt(0);
  final version = db.select('PRAGMA user_version').single.columnAt(0);
  if (applicationId != formatApplicationId || version is! int || version < 1) {
    throw ModuleOpenException(const NotHisbibleModule());
  }
  if (version > formatVersion) {
    throw ModuleOpenException(NewerFormat(version));
  }

  return ModuleMeta.fromValues(readMetaValues(db));
}

/// Пары `meta` открытой базы; без таблицы — [MissingTable] в исключении.
Map<String, String> readMetaValues(Database db) {
  if (!_columnsOf(db, metaTable.name).containsAll(metaTable.columns)) {
    throw ModuleOpenException(MissingTable(metaTable.name));
  }

  return {
    for (final row in db.select('SELECT key, value FROM meta'))
      if (row.columnAt(0) case final String key)
        if (row.columnAt(1) case final Object value) key: '$value',
  };
}

/// Номера книг из `books` по их кодам; код, которого справочник не знает,
/// и повтор номера пропускаются.
Map<String, int> readBookCodes(Database db) {
  final codes = <String, int>{};
  final seen = <int>{};
  for (final row in db.select('SELECT code FROM books ORDER BY position')) {
    final code = row.columnAt(0);
    final number = code is String ? BookCatalog.numberOfCode(code) : null;
    if (number != null && seen.add(number)) {
      codes[code as String] = number;
    }
  }

  return codes;
}

// Имена столбцов [table]; пусто, если таблицы нет.
Set<String> _columnsOf(Database db, String table) => {
  for (final row in db.select('PRAGMA table_info("$table")'))
    if (row['name'] case final String name) name.toLowerCase(),
};

// Есть ли в модуле что читать: стих, толкование или ссылка.
bool _hasReadableContent(Database db, ModuleType type) => switch (type) {
  ModuleType.bible => _hasReadableVerse(db),
  ModuleType.commentaries => _hasKnownBook(db, 'comments'),
  ModuleType.crossReferences => _hasKnownBook(db, 'crossrefs'),
};

// Есть ли в [table] запись с книгой, которую знает справочник, главой и
// стихом не меньше 1.
bool _hasKnownBook(Database db, String table) {
  for (final row in db.select(
    'SELECT DISTINCT book FROM $table WHERE chapter >= 1 AND verse >= 1',
  )) {
    final code = row.columnAt(0);
    if (code is String && BookCatalog.numberOfCode(code) != null) {
      return true;
    }
  }

  return false;
}

// Есть ли стих книги из `books` с главой и стихом не меньше 1.
bool _hasReadableVerse(Database db) {
  final codes = readBookCodes(db).keys.toList();
  if (codes.isEmpty) {
    return false;
  }

  return db
      .select(
        'SELECT 1 FROM verses WHERE book IN '
        '(${List.filled(codes.length, '?').join(', ')}) '
        'AND chapter >= 1 AND verse >= 1 LIMIT 1',
        codes,
      )
      .isNotEmpty;
}
