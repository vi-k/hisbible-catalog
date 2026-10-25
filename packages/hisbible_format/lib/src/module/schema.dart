import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';

/// Версия формата файла модуля, которую пишет и читает этот пакет.
///
/// Хранится в `PRAGMA user_version`; растёт только при несовместимом
/// изменении. Читатель версии `N` открывает файлы версий `1..N`.
const int formatVersion = 1;

/// Подпись файла модуля HisBible в `PRAGMA application_id`.
///
/// `0x48694269` — байты «HiBi».
const int formatApplicationId = 1214857833;

/// Направление письма модуля.
enum WritingDirection {
  /// Слева направо.
  ltr,

  /// Справа налево.
  rtl,
}

/// Вид заголовка над стихом.
enum HeadingKind {
  /// Большой раздел, над несколькими разделами.
  major,

  /// Заголовок раздела.
  section,

  /// Надписание: часть текста (надписание псалма).
  title,
}

/// Вид сноски.
enum FootnoteKind {
  /// Примечание.
  note,

  /// Перекрёстная ссылка.
  crossref,
}

/// Откуда книга в модуле.
enum BookKind {
  /// Каноническая книга справочника.
  canonical,

  /// Неканоническая книга справочника.
  deuterocanonical,

  /// Номер, которого нет в справочнике книг.
  outsideTable,
}

/// Таблица схемы версии 1: имя, обязательные столбцы и `CREATE`.
typedef SchemaTable = ({String name, List<String> columns, String create});

/// Таблица `meta`: ключи и значения модуля.
const SchemaTable metaTable = (
  name: 'meta',
  columns: ['key', 'value'],
  create:
      'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) '
      'WITHOUT ROWID',
);

/// Таблица `books`: книги Библии в порядке модуля.
const SchemaTable booksTable = (
  name: 'books',
  columns: [
    'position',
    'code',
    'short_name',
    'long_name',
    'title',
    'scheme',
    'color',
  ],
  create: '''
CREATE TABLE books (
  position INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  short_name TEXT NOT NULL,
  long_name TEXT NOT NULL,
  title TEXT,
  scheme TEXT NOT NULL,
  color INTEGER
)''',
);

/// Таблица `verses`: стихи Библии.
const SchemaTable versesTable = (
  name: 'verses',
  columns: ['book', 'chapter', 'verse', 'verse_end', 'text'],
  create: '''
CREATE TABLE verses (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  verse_end INTEGER,
  text TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse)
) WITHOUT ROWID''',
);

/// Таблица `headings`: заголовки над стихами.
const SchemaTable headingsTable = (
  name: 'headings',
  columns: ['book', 'chapter', 'verse', 'position', 'kind', 'level', 'text'],
  create: '''
CREATE TABLE headings (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,
  level INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse, position)
) WITHOUT ROWID''',
);

/// Таблица `footnotes`: сноски стихов.
const SchemaTable footnotesTable = (
  name: 'footnotes',
  columns: ['id', 'book', 'chapter', 'verse', 'kind', 'caller', 'text'],
  create: '''
CREATE TABLE footnotes (
  id INTEGER PRIMARY KEY,
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  kind TEXT NOT NULL,
  caller TEXT NOT NULL,
  text TEXT NOT NULL
)''',
);

/// Таблица `comments`: толкования.
const SchemaTable commentsTable = (
  name: 'comments',
  columns: [
    'id',
    'book',
    'chapter',
    'verse',
    'chapter_end',
    'verse_end',
    'text',
  ],
  create: '''
CREATE TABLE comments (
  id INTEGER PRIMARY KEY,
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  chapter_end INTEGER, verse_end INTEGER,
  text TEXT NOT NULL
)''',
);

/// Таблица `crossrefs`: перекрёстные ссылки.
const SchemaTable crossrefsTable = (
  name: 'crossrefs',
  columns: [
    'book',
    'chapter',
    'verse',
    'verse_end',
    'to_book',
    'to_chapter',
    'to_verse',
    'to_chapter_end',
    'to_verse_end',
    'votes',
  ],
  create: '''
CREATE TABLE crossrefs (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  verse_end INTEGER,
  to_book TEXT NOT NULL, to_chapter INTEGER NOT NULL, to_verse INTEGER NOT NULL,
  to_chapter_end INTEGER, to_verse_end INTEGER,
  votes INTEGER NOT NULL DEFAULT 0
)''',
);

/// Таблицы модуля типа [type] в порядке создания и проверки.
List<SchemaTable> tablesOf(ModuleType type) => switch (type) {
  ModuleType.bible => const [
    metaTable,
    booksTable,
    versesTable,
    headingsTable,
    footnotesTable,
  ],
  ModuleType.commentaries => const [metaTable, commentsTable],
  ModuleType.crossReferences => const [metaTable, crossrefsTable],
};

/// Индексы модуля типа [type]; создаются после записи данных.
List<String> indexesOf(ModuleType type) => switch (type) {
  ModuleType.bible => const [
    'CREATE INDEX footnotes_place ON footnotes (book, chapter, verse)',
  ],
  ModuleType.commentaries => const [
    'CREATE INDEX comments_place ON comments (book, chapter, verse)',
  ],
  ModuleType.crossReferences => const [
    'CREATE INDEX crossrefs_place ON crossrefs (book, chapter, verse)',
  ],
};

/// Значение `meta` `type` для [type].
String typeValue(ModuleType type) => switch (type) {
  ModuleType.bible => 'bible',
  ModuleType.commentaries => 'commentaries',
  ModuleType.crossReferences => 'crossreferences',
};

/// Тип модуля по значению `meta` `type` или `null`, если тип незнаком.
ModuleType? typeOfValue(String value) => switch (value) {
  'bible' => ModuleType.bible,
  'commentaries' => ModuleType.commentaries,
  'crossreferences' => ModuleType.crossReferences,
  _ => null,
};

/// Схема нумерации по значению столбца `scheme` или `null`.
VerseScheme? schemeOfValue(Object? value) {
  for (final scheme in VerseScheme.values) {
    if (scheme.name == value) {
      return scheme;
    }
  }

  return null;
}

/// Вид заголовка по значению столбца `kind` или `null`.
HeadingKind? headingKindOfValue(Object? value) {
  for (final kind in HeadingKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }

  return null;
}

/// Вид сноски по значению столбца `kind` или `null`.
FootnoteKind? footnoteKindOfValue(Object? value) {
  for (final kind in FootnoteKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }

  return null;
}
