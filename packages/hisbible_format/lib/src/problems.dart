// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Что не так с архивом.
enum ArchiveProblemKind {
  /// Файл не zip: нет заголовка записи zip.
  notZip,

  /// Zip обрезан или повреждён: недокачан, битые записи.
  truncated,
}

/// Причина, по которой файл не годится как модуль; равенство — по полям.
sealed class ModuleProblem {
  const ModuleProblem();
}

/// Файл не является базой SQLite.
final class NotSqlite extends ModuleProblem {
  /// Создаёт причину.
  const NotSqlite();

  @override
  bool operator ==(Object other) => other is NotSqlite;

  @override
  int get hashCode => (NotSqlite).hashCode;

  @override
  String toString() => 'NotSqlite()';
}

/// В модуле нет обязательной таблицы.
final class MissingTable extends ModuleProblem {
  /// Создаёт причину для таблицы [table].
  const MissingTable(this.table);

  /// Имя недостающей таблицы.
  final String table;

  @override
  bool operator ==(Object other) =>
      other is MissingTable && other.table == table;

  @override
  int get hashCode => Object.hash(MissingTable, table);

  @override
  String toString() => 'MissingTable($table)';
}

/// В таблице модуля нет обязательного столбца.
final class MissingColumn extends ModuleProblem {
  /// Создаёт причину для столбца [column] таблицы [table].
  const MissingColumn(this.table, this.column);

  /// Имя таблицы.
  final String table;

  /// Имя недостающего столбца.
  final String column;

  @override
  bool operator ==(Object other) =>
      other is MissingColumn && other.table == table && other.column == column;

  @override
  int get hashCode => Object.hash(MissingColumn, table, column);

  @override
  String toString() => 'MissingColumn($table, $column)';
}

/// В Библии нет ни одного стиха.
final class EmptyModule extends ModuleProblem {
  /// Создаёт причину.
  const EmptyModule();

  @override
  bool operator ==(Object other) => other is EmptyModule;

  @override
  int get hashCode => (EmptyModule).hashCode;

  @override
  String toString() => 'EmptyModule()';
}

/// Номера стиха Библии вне границ формата: глава больше 200
/// (`maxChapterNumber`), стих больше 1000 (`maxVerseNumber`) или
/// `verse_end` больше стиха больше чем на 200 (`maxVerseEndSpan`). Файл
/// испорчен или собран со злым умыслом.
final class VerseOutOfRange extends ModuleProblem {
  /// Создаёт причину для стиха [chapter]:[verse] книги с кодом [book].
  const VerseOutOfRange(this.book, this.chapter, this.verse);

  /// Код книги в файле.
  final String book;

  /// Глава.
  final int chapter;

  /// Стих; у слитых стихов — первый.
  final int verse;

  @override
  bool operator ==(Object other) =>
      other is VerseOutOfRange &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(VerseOutOfRange, book, chapter, verse);

  @override
  String toString() => 'VerseOutOfRange($book $chapter:$verse)';
}

/// В модуле есть объект схемы, кроме таблиц и их индексов: представление,
/// триггер или виртуальная таблица. Запрос к такому модулю может зависнуть
/// или сделать то, чего читатель не ждёт.
final class UnsupportedSchemaObject extends ModuleProblem {
  /// Создаёт причину для объекта [name] вида [type].
  const UnsupportedSchemaObject(this.type, this.name);

  /// Вид объекта: `view`, `trigger`, `virtual table` или другой `type`
  /// из `sqlite_master`.
  final String type;

  /// Имя объекта.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is UnsupportedSchemaObject &&
      other.type == type &&
      other.name == name;

  @override
  int get hashCode => Object.hash(UnsupportedSchemaObject, type, name);

  @override
  String toString() => 'UnsupportedSchemaObject($type $name)';
}

/// Тип модуля приложение не читает.
final class UnsupportedType extends ModuleProblem {
  /// Создаёт причину для [suffix]: имени типа или значения `type`.
  const UnsupportedType(this.suffix);

  /// Имя типа, которого читающий класс не открывает (`commentaries`, если
  /// Библию открывают как толкования), или незнакомое значение `type`.
  final String suffix;

  @override
  bool operator ==(Object other) =>
      other is UnsupportedType && other.suffix == suffix;

  @override
  int get hashCode => Object.hash(UnsupportedType, suffix);

  @override
  String toString() => 'UnsupportedType($suffix)';
}

/// Имя файла не похоже на модуль: расширение не то.
final class NotAModuleFile extends ModuleProblem {
  /// Создаёт причину.
  const NotAModuleFile();

  @override
  bool operator ==(Object other) => other is NotAModuleFile;

  @override
  int get hashCode => (NotAModuleFile).hashCode;

  @override
  String toString() => 'NotAModuleFile()';
}

/// В архиве нет ни одного модуля.
final class NoModulesInArchive extends ModuleProblem {
  /// Создаёт причину.
  const NoModulesInArchive();

  @override
  bool operator ==(Object other) => other is NoModulesInArchive;

  @override
  int get hashCode => (NoModulesInArchive).hashCode;

  @override
  String toString() => 'NoModulesInArchive()';
}

/// Архив не читается как zip: не zip или обрезан.
final class BrokenArchive extends ModuleProblem {
  /// Создаёт причину вида [kind].
  const BrokenArchive(this.kind);

  /// Что не так с архивом.
  final ArchiveProblemKind kind;

  @override
  bool operator ==(Object other) =>
      other is BrokenArchive && other.kind == kind;

  @override
  int get hashCode => Object.hash(BrokenArchive, kind);

  @override
  String toString() => 'BrokenArchive(${kind.name})';
}

/// Файл не удалось прочитать по другой причине.
final class Unreadable extends ModuleProblem {
  /// Создаёт причину с сообщением [message].
  const Unreadable(this.message);

  /// Сообщение системы или SQLite без пути к файлу; пустое — система
  /// причины не назвала.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is Unreadable && other.message == message;

  @override
  int get hashCode => Object.hash(Unreadable, message);

  @override
  String toString() => 'Unreadable($message)';
}

/// База SQLite, но не модуль HisBible: нет подписи формата.
final class NotHisbibleModule extends ModuleProblem {
  /// Создаёт причину.
  const NotHisbibleModule();

  @override
  bool operator ==(Object other) => other is NotHisbibleModule;

  @override
  int get hashCode => (NotHisbibleModule).hashCode;

  @override
  String toString() => 'NotHisbibleModule()';
}

/// Модуль записан в версии формата новее, чем знает читатель.
final class NewerFormat extends ModuleProblem {
  /// Создаёт причину для версии [version].
  const NewerFormat(this.version);

  /// Версия формата файла.
  final int version;

  @override
  bool operator ==(Object other) =>
      other is NewerFormat && other.version == version;

  @override
  int get hashCode => Object.hash(NewerFormat, version);

  @override
  String toString() => 'NewerFormat($version)';
}

/// В `meta` модуля нет обязательного ключа или он пуст.
final class MissingMeta extends ModuleProblem {
  /// Создаёт причину для ключа [key].
  const MissingMeta(this.key);

  /// Недостающий ключ.
  final String key;

  @override
  bool operator ==(Object other) => other is MissingMeta && other.key == key;

  @override
  int get hashCode => Object.hash(MissingMeta, key);

  @override
  String toString() => 'MissingMeta($key)';
}

/// Модуль не удалось перевести в формат HisBible.
final class ConversionFailed extends ModuleProblem {
  /// Создаёт причину с сообщением [message].
  const ConversionFailed(this.message);

  /// Что не так, без пути к файлу.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ConversionFailed && other.message == message;

  @override
  int get hashCode => Object.hash(ConversionFailed, message);

  @override
  String toString() => 'ConversionFailed($message)';
}

/// Модуль не открылся; причина — в [problem].
final class ModuleOpenException implements Exception {
  /// Создаёт исключение для причины [problem].
  ModuleOpenException(this.problem);

  /// Почему модуль не открылся.
  final ModuleProblem problem;

  @override
  String toString() => 'ModuleOpenException($problem)';
}
