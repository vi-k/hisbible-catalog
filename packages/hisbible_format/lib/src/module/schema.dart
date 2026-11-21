import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';

/// Версия формата файла модуля, которую пишет и читает этот пакет.
///
/// Хранится в `PRAGMA user_version`; растёт только при несовместимом
/// изменении. Читатель версии `N` открывает файлы версий `1..N`.
///
/// Версия 2 хранит куски стихов: строка `verses` — кусок с местом в главе
/// (`position`) и частями концов (`part`, `part_end`); заголовки, метки
/// и номера стихов привязаны к куску (`verse`, `part`).
const int formatVersion = 2;

/// Подпись файла модуля HisBible в `PRAGMA application_id`.
///
/// `0x48694269` — байты «HiBi».
const int formatApplicationId = 1214857833;

/// На сколько `verse_end` слитых стихов может быть больше `verse`.
///
/// Больший `verse_end` — негодный файл: `VerseOutOfRange` у
/// `checkModuleFile`.
const int maxVerseEndSpan = 200;

/// Наибольший номер главы в `verses`: в самой длинной книге, Псалтири,
/// 150 глав. Больший — негодный файл: `VerseOutOfRange`.
const int maxChapterNumber = 200;

/// Наибольший номер стиха в `verses`: в самой длинной главе, Псалме 118
/// (119), 176 стихов. Больший — негодный файл: `VerseOutOfRange`.
const int maxVerseNumber = 1000;

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

/// Вид части вступления книги или предисловия модуля.
enum IntroKind {
  /// Заглавие вступления.
  title,

  /// Абзац вступления.
  paragraph,

  /// Название статьи предисловия модуля: с него начинается статья, и она
  /// идёт до следующего названия. Во вступлении книги не бывает.
  article,

  /// Строка списка: абзац без красной строки (`\ili`), как строки списка
  /// сокращений.
  item,

  /// Автор статьи предисловия модуля: стоит сразу за её названием, в тексте
  /// статьи не показывается. Во вступлении книги не бывает.
  author,

  /// Главная строка заглавия книги (`\mt`, `\mt1`): «Бытие». Строки
  /// заглавия стоят в начале вступления, до его частей; есть они — читатель
  /// показывает их вместо полного заглавия книги (`books.title`).
  /// В предисловии модуля не бывает.
  bookTitle,

  /// Строка заглавия книги мельче главной (`\mt2`, `\mt3`…): «Первая книга
  /// Моисея» над «Бытие». Стоит над главной строкой или под ней — по
  /// порядку частей.
  bookSubtitle,
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

/// Таблица схемы: имя, обязательные столбцы и `CREATE`.
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

/// Таблица `verses`: куски стихов Библии в порядке главы.
///
/// Кусок идёт от `verse`/`part` до `verse_end`/`part_end`; `part` — буква
/// части, пустая — стих целиком; `verse_end` `NULL` — кусок в одном стихе.
/// `position` — место куска в главе, с 0.
const SchemaTable versesTable = (
  name: 'verses',
  columns: [
    'book',
    'chapter',
    'position',
    'verse',
    'part',
    'verse_end',
    'part_end',
    'text',
  ],
  create: '''
CREATE TABLE verses (
  book TEXT NOT NULL, chapter INTEGER NOT NULL,
  position INTEGER NOT NULL,
  verse INTEGER NOT NULL, part TEXT NOT NULL,
  verse_end INTEGER, part_end TEXT NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (book, chapter, position),
  UNIQUE (book, chapter, verse, part)
) WITHOUT ROWID''',
);

/// Таблица `verses` версии 1: стихи по номерам, без частей и места в главе.
const SchemaTable versesTableV1 = (
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

/// Таблица `headings`: заголовки над кусками стихов.
const SchemaTable headingsTable = (
  name: 'headings',
  columns: [
    'book',
    'chapter',
    'verse',
    'part',
    'position',
    'kind',
    'level',
    'text',
  ],
  create: '''
CREATE TABLE headings (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,
  level INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse, part, position)
) WITHOUT ROWID''',
);

/// Таблица `headings` версии 1: заголовки над стихами.
const SchemaTable headingsTableV1 = (
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

/// Код книги в `intros`, под которым лежит предисловие модуля — вводные
/// страницы издания перед всеми книгами (код USFM `FRT`, front matter).
const String prefaceBookCode = 'FRT';

/// Таблица `intros`: вступления книг и предисловие модуля (строки
/// с книгой [prefaceBookCode]).
///
/// Необязательная, только у Библии: в [tablesOf] её нет, писатель создаёт её
/// при первом вступлении, читатель смотрит, есть ли она в файле.
const SchemaTable introsTable = (
  name: 'intros',
  columns: ['book', 'position', 'kind', 'text'],
  create: '''
CREATE TABLE intros (
  book TEXT NOT NULL,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (book, position)
) WITHOUT ROWID''',
);

/// Таблица `verse_labels`: метки кусков стихов вместо номеров.
///
/// Необязательная, только у Библии: в [tablesOf] её нет, писатель создаёт её
/// при первой метке, читатель смотрит, есть ли она в файле.
const SchemaTable verseLabelsTable = (
  name: 'verse_labels',
  columns: ['book', 'chapter', 'verse', 'part', 'label'],
  create: '''
CREATE TABLE verse_labels (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,
  label TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse, part)
) WITHOUT ROWID''',
);

/// Таблица `verse_labels` версии 1: метки стихов вместо номеров.
const SchemaTable verseLabelsTableV1 = (
  name: 'verse_labels',
  columns: ['book', 'chapter', 'verse', 'label'],
  create: '''
CREATE TABLE verse_labels (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  label TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse)
) WITHOUT ROWID''',
);

/// Таблица `verse_numbers`: номера кусков стихов, как их печатает издание.
///
/// Необязательная, только у Библии: в [tablesOf] её нет, писатель создаёт её
/// при первом номере, читатель смотрит, есть ли она в файле.
const SchemaTable verseNumbersTable = (
  name: 'verse_numbers',
  columns: ['book', 'chapter', 'verse', 'part', 'number'],
  create: '''
CREATE TABLE verse_numbers (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,
  number TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse, part)
) WITHOUT ROWID''',
);

/// Таблица `verse_numbers` версии 1: номера стихов, как их печатает издание.
const SchemaTable verseNumbersTableV1 = (
  name: 'verse_numbers',
  columns: ['book', 'chapter', 'verse', 'number'],
  create: '''
CREATE TABLE verse_numbers (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  number TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse)
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

/// Таблицы модуля типа [type] версии формата [version] в порядке создания
/// и проверки.
List<SchemaTable> tablesOf(ModuleType type, {int version = formatVersion}) =>
    switch (type) {
      ModuleType.bible when version == 1 => const [
        metaTable,
        booksTable,
        versesTableV1,
        headingsTableV1,
        footnotesTable,
      ],
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

/// Необязательные таблицы Библии версии формата [version]: `intros`,
/// `verse_labels` и `verse_numbers`.
List<SchemaTable> optionalBibleTablesOf(int version) => version == 1
    ? const [introsTable, verseLabelsTableV1, verseNumbersTableV1]
    : const [introsTable, verseLabelsTable, verseNumbersTable];

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

/// Вид части вступления по значению столбца `kind` или `null`.
IntroKind? introKindOfValue(Object? value) {
  for (final kind in IntroKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }

  return null;
}
