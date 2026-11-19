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

/// Ключ куска стиха в главе: стих, которым он начинается, и часть этого
/// стиха; пустая часть — стих целиком.
typedef PieceKey = ({int verse, String part});

/// Кусок стиха главы: от [verse] с частью [part] до [verseEnd] с частью
/// [partEnd].
///
/// Кусок без частей и без [verseEnd] — обычный стих; без частей с
/// [verseEnd] — слитые стихи.
final class Verse {
  /// Создаёт кусок; [verseEnd] — последний стих куска, [part] и [partEnd] —
  /// части первого и последнего стиха, пустые — стих целиком.
  const Verse(
    this.verse,
    this.text, {
    this.verseEnd,
    this.part = '',
    this.partEnd = '',
  });

  /// Номер первого стиха куска.
  final int verse;

  /// Текст куска в разметке формата.
  final String text;

  /// Последний стих куска; `null` — кусок в одном стихе.
  final int? verseEnd;

  /// Буква части первого стиха (`a`, `б`); пустая — стих целиком.
  final String part;

  /// Буква части последнего стиха; пустая — стих целиком. Без [verseEnd]
  /// пустая.
  final String partEnd;

  /// Ключ куска в главе: первый стих и его часть.
  PieceKey get key => (verse: verse, part: part);

  /// Номер куска из его концов: `6`, `6b`, `10b–14`, `1–6а`.
  String get label =>
      verseEnd == null ? '$verse$part' : '$verse$part–$verseEnd$partEnd';

  /// Есть ли в куске стих [verse], целиком или частью.
  bool covers(int verse) =>
      verse >= this.verse && verse <= (verseEnd ?? this.verse);

  @override
  bool operator ==(Object other) =>
      other is Verse &&
      other.verse == verse &&
      other.text == text &&
      other.verseEnd == verseEnd &&
      other.part == part &&
      other.partEnd == partEnd;

  @override
  int get hashCode => Object.hash(verse, text, verseEnd, part, partEnd);

  @override
  String toString() => 'Verse($label, $text)';
}

/// Заголовок над куском стиха.
final class Heading {
  /// Создаёт заголовок; [part] — часть стиха, которой начинается кусок.
  const Heading(
    this.verse,
    this.order,
    this.kind,
    this.level,
    this.text, {
    this.part = '',
  });

  /// Номер стиха, которым начинается кусок под заголовком.
  final int verse;

  /// Часть стиха, которой начинается кусок под заголовком; пустая — стих
  /// целиком.
  final String part;

  /// Порядок среди заголовков одного куска, с 0.
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
      other.part == part &&
      other.order == order &&
      other.kind == kind &&
      other.level == level &&
      other.text == text;

  @override
  int get hashCode => Object.hash(verse, part, order, kind, level, text);

  @override
  String toString() =>
      'Heading($verse$part, $order, ${kind.name}, $level, $text)';
}

/// Часть вступления книги.
final class Intro {
  /// Создаёт часть вступления.
  const Intro(this.position, this.kind, this.text);

  /// Номер части в книге, с 0.
  final int position;

  /// Вид части.
  final IntroKind kind;

  /// Текст части в разметке формата.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Intro &&
      other.position == position &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(position, kind, text);

  @override
  String toString() => 'Intro($position, ${kind.name}, $text)';
}

/// Статья предисловия модуля: название, автор и части после них.
final class PrefaceArticle {
  /// Создаёт статью.
  const PrefaceArticle(this.title, this.parts, {this.author});

  /// Название статьи в разметке формата; `null` — части перед первым
  /// названием, у них своего названия нет.
  final String? title;

  /// Части статьи по порядку, без её названия и автора.
  final List<Intro> parts;

  /// Автор статьи в разметке формата (часть [IntroKind.author]); `null` —
  /// не указан.
  final String? author;

  @override
  bool operator ==(Object other) {
    if (other is! PrefaceArticle ||
        other.title != title ||
        other.author != author ||
        other.parts.length != parts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      if (other.parts[i] != parts[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(title, author, Object.hashAll(parts));

  @override
  String toString() => 'PrefaceArticle($title, $parts, author: $author)';
}

/// Сноска к стиху или к предисловию модуля.
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

  /// Номер книги справочника; у сноски предисловия — 0.
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

// Номера книг справочника: 2 Паралипоменон и Молитва Манассии.
const _chroniclesBook = 140;
const _manassehBook = 145;

/// Открытый модуль Библии формата HisBible; файл читается только на чтение.
final class BibleModule {
  BibleModule._(
    this._db,
    this._version,
    this.meta,
    this.books,
    this._codes,
    this._lastVerses,
    this.hasParagraphMarks,
    this._hasIntros,
    this._hasVerseLabels,
    this._hasVerseNumbers,
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
      final version = moduleFormatVersion(db);
      final codes = readBookCodes(db);
      final lastVerses = _readLastVerses(db, version, codes);
      final module = BibleModule._(
        db,
        version,
        meta,
        _readBooks(db, codes, lastVerses),
        {for (final MapEntry(:key, :value) in codes.entries) value: key},
        lastVerses,
        readMetaValues(db)['paragraphs'] == '1',
        hasModuleTable(db, introsTable.name),
        hasModuleTable(db, verseLabelsTable.name),
        hasModuleTable(db, verseNumbersTable.name),
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
  // Версия формата файла: у версии 1 нет частей и места куска в главе.
  final int _version;
  // Номер книги → код в файле.
  final Map<int, String> _codes;
  final Map<int, Map<int, int>> _lastVerses;
  final Map<int, ModuleBook> _byNumber;
  // Есть ли в файле необязательная таблица `intros`.
  final bool _hasIntros;
  // Есть ли в файле необязательная таблица `verse_labels`.
  final bool _hasVerseLabels;
  // Есть ли в файле необязательная таблица `verse_numbers`.
  final bool _hasVerseNumbers;
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
  ///
  /// Дом Молитвы Манассии [BookSchemes.manasseh]: есть книга 145 —
  /// [ManassehHome.book]; иначе у 2 Пар 36 больше 23 стихов —
  /// [ManassehHome.chronicles36]; иначе есть 2 Пар 37 —
  /// [ManassehHome.chronicles37]; иначе [ManassehHome.book].
  BookSchemes get schemes => BookSchemes(
    schemes: {for (final book in books) book.number: book.scheme},
    manasseh: _manasseh,
  );

  // Дом Молитвы Манассии по книгам и главам модуля; правило — у [schemes].
  ManassehHome get _manasseh {
    if (_byNumber.containsKey(_manassehBook)) {
      return ManassehHome.book;
    }
    final chronicles = _lastVerses[_chroniclesBook] ?? const {};
    if ((chronicles[36] ?? 0) > 23) {
      return ManassehHome.chronicles36;
    }

    return chronicles.containsKey(37)
        ? ManassehHome.chronicles37
        : ManassehHome.book;
  }

  /// Есть ли в стихах `<p/>`: ключ `meta` `paragraphs` равен `1`.
  ///
  /// Модуль без `<p/>` показывает сплошной текст.
  final bool hasParagraphMarks;

  /// Книга → глава → последний стих; у слитых стихов — по `verse_end`.
  Map<int, Map<int, int>> lastVerses() => {
    for (final MapEntry(:key, :value) in _lastVerses.entries)
      key: Map<int, int>.of(value),
  };

  /// Куски стихов главы по их месту в главе (`position`); у файла версии 1
  /// — стихи по возрастанию номеров, без частей.
  ///
  /// `verse_end`, который не больше `verse`, больше его больше чем на
  /// [maxVerseEndSpan] или заходит на следующий по номерам кусок главы,
  /// читается как `null` вместе с `part_end`: кусок в одном стихе. Концы
  /// сравниваются парами (стих, часть), пустая часть раньше любой буквы:
  /// `28–29` перед `29a` годен, `1–7b` перед `7b` — нет.
  List<Verse> chapter(int book, int chapter) {
    final code = _codes[book];
    if (code == null) {
      return const [];
    }

    return [
      for (final row in _db.select(
        'SELECT verse, part, $_verseEndRule, part_end, text '
        'FROM (${_pieces(_version)} WHERE book = ? AND chapter = ? '
        'AND verse >= 1) ORDER BY place',
        [code, chapter],
      ))
        if ((row.columnAt(0), row.columnAt(1), row.columnAt(4)) case (
          final int verse,
          final String part,
          final String text,
        ))
          Verse(
            verse,
            text,
            verseEnd: row.columnAt(2) as int?,
            part: part,
            partEnd: _partEnd(row.columnAt(2), row.columnAt(3)),
          ),
    ];
  }

  /// Вступление книги по `position`; незнакомый вид пропускается.
  ///
  /// Пусто, если в файле нет таблицы `intros` или вступления у книги.
  List<Intro> intros(int book) {
    final code = _codes[book];

    return code == null ? const [] : _introsOf(code);
  }

  /// Предисловие модуля — вводные страницы издания перед всеми книгами
  /// (строки `intros` с книгой [prefaceBookCode]) — по `position`;
  /// незнакомый вид пропускается.
  ///
  /// Пусто, если в файле нет таблицы `intros` или предисловия.
  List<Intro> preface() => _introsOf(prefaceBookCode);

  /// Предисловие модуля по статьям: каждая часть [IntroKind.article]
  /// открывает статью со своим названием. Части перед первым названием —
  /// статья без названия; предисловие без названий — одна такая статья.
  /// Статья без частей остаётся: у неё есть название. Часть
  /// [IntroKind.author] — автор своей статьи, а не её часть.
  ///
  /// Пусто, если предисловия нет.
  List<PrefaceArticle> prefaceArticles() {
    final articles = <PrefaceArticle>[];
    String? title;
    String? author;
    var parts = <Intro>[];
    var opened = false;
    void close() {
      if (opened || parts.isNotEmpty || author != null) {
        articles.add(
          PrefaceArticle(title, List.unmodifiable(parts), author: author),
        );
      }
    }

    for (final part in preface()) {
      switch (part.kind) {
        case IntroKind.article:
          close();
          title = part.text;
          author = null;
          parts = [];
          opened = true;
        case IntroKind.author:
          author = part.text;
        case IntroKind.title || IntroKind.paragraph || IntroKind.item:
          parts.add(part);
      }
    }
    close();

    return articles;
  }

  List<Intro> _introsOf(String code) {
    if (!_hasIntros) {
      return const [];
    }

    return [
      for (final row in _db.select(
        'SELECT position, kind, text FROM intros WHERE book = ? '
        'ORDER BY position',
        [code],
      ))
        if ((
              row.columnAt(0),
              introKindOfValue(row.columnAt(1)),
              row.columnAt(2),
            )
            case (final int position, final IntroKind kind, final String text))
          Intro(position, kind, text),
    ];
  }

  /// Метки кусков главы вместо номеров: ключ куска → метка.
  ///
  /// У куска с меткой в тексте нет номера; непустая метка стоит в конце
  /// куска. Пусто, если в файле нет таблицы `verse_labels` или меток у главы.
  /// У файла версии 1 части ключей пустые.
  Map<PieceKey, String> verseLabels(int book, int chapter) {
    final code = _codes[book];
    if (!_hasVerseLabels || code == null) {
      return const {};
    }

    return _pieceValues('verse_labels', 'label', code, chapter);
  }

  /// Номера кусков главы, как их печатает издание, когда их не построить
  /// из концов куска: ключ куска → номер.
  ///
  /// Текст показывает такой номер вместо своего; адрес куска прежний. Пусто,
  /// если в файле нет таблицы `verse_numbers` или номеров у главы. У файла
  /// версии 1 части ключей пустые.
  Map<PieceKey, String> verseNumbers(int book, int chapter) {
    final code = _codes[book];
    if (!_hasVerseNumbers || code == null) {
      return const {};
    }

    return _pieceValues('verse_numbers', 'number', code, chapter);
  }

  // Значения столбца [column] таблицы [table] у кусков главы по номерам.
  Map<PieceKey, String> _pieceValues(
    String table,
    String column,
    String code,
    int chapter,
  ) => {
    for (final row in _db.select(
      'SELECT verse, $_part, $column FROM $table '
      'WHERE book = ? AND chapter = ? ORDER BY $_byNumbers',
      [code, chapter],
    ))
      if ((row.columnAt(0), row.columnAt(1), row.columnAt(2)) case (
        final int verse,
        final String part,
        final String value,
      ))
        (verse: verse, part: part): value,
  };

  /// Заголовки главы по кускам и порядку; незнакомый вид пропускается.
  List<Heading> headings(int book, int chapter) {
    final code = _codes[book];
    if (code == null) {
      return const [];
    }

    return [
      for (final row in _db.select(
        'SELECT verse, $_part, position, kind, level, text FROM headings '
        'WHERE book = ? AND chapter = ? ORDER BY $_byNumbers, position',
        [code, chapter],
      ))
        if ((
              row.columnAt(0),
              row.columnAt(1),
              row.columnAt(2),
              headingKindOfValue(row.columnAt(3)),
              row.columnAt(4),
              row.columnAt(5),
            )
            case (
              final int verse,
              final String part,
              final int order,
              final HeadingKind kind,
              final int level,
              final String text,
            ))
          Heading(verse, order, kind, level, text, part: part),
    ];
  }

  // Столбец части в запросах: у файла версии 1 частей нет — пустая строка.
  String get _part => _partOf(_version);

  // Порядок кусков по номерам в запросах.
  String get _byNumbers => _byNumbersOf(_version);

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

  /// Сноски предисловия модуля (строки `footnotes` с книгой
  /// [prefaceBookCode]) по номерам; у них [Footnote.book], глава и стих — 0.
  /// Незнакомый вид пропускается.
  List<Footnote> prefaceFootnotes() => [
    for (final row in _db.select(
      'SELECT id, kind, caller, text FROM footnotes WHERE book = ? ORDER BY id',
      [prefaceBookCode],
    ))
      if ((
            row.columnAt(0),
            footnoteKindOfValue(row.columnAt(1)),
            row.columnAt(2),
            row.columnAt(3),
          )
          case (
            final int id,
            final FootnoteKind kind,
            final String caller,
            final String text,
          ))
        Footnote(id, 0, 0, 0, kind, caller, text),
  ];

  /// Закрывает базу; повторный вызов ничего не делает.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _db.close();
  }

  // Часть последнего стиха куска с концом [verseEnd] по значению [value]
  // столбца `part_end`: без конца или не строка — пустая.
  static String _partEnd(Object? verseEnd, Object? value) =>
      verseEnd != null && value is String ? value : '';

  // Столбец части в запросах к файлу версии [version].
  static String _partOf(int version) => version == 1 ? "''" : 'part';

  // Порядок кусков по номерам в запросах к файлу версии [version]: стих,
  // затем часть.
  static String _byNumbersOf(int version) =>
      version == 1 ? 'verse' : 'verse, part';

  // Запрос кусков `verses` файла версии [version] без условия: место куска
  // в главе (`place`), его концы и текст, а также следующий по номерам кусок
  // (`next`, `next_part`) среди строк, которые пройдут условие. У версии 1
  // место — номер стиха, части пустые. Условие дописывает вызывающий.
  static String _pieces(int version) {
    final part = _partOf(version);
    final numbers =
        'OVER (PARTITION BY book, chapter ORDER BY ${_byNumbersOf(version)})';

    return 'SELECT book, chapter, '
        '${version == 1 ? 'verse' : 'position'} AS place, verse, '
        '$part AS part, verse_end, ${version == 1 ? "''" : 'part_end'} '
        'AS part_end, text, LEAD(verse) $numbers AS next, '
        'LEAD($part) $numbers AS next_part FROM verses';
  }

  // Годный последний стих куска из [_pieces] или NULL: `verse_end`, если он
  // больше `verse` не больше чем на [maxVerseEndSpan] и кончается до
  // следующего по номерам куска главы. Концы сравниваются парами (стих,
  // часть), пустая часть раньше любой буквы: `6b–10a` перед `10b` и `28–29`
  // перед добавлением `29a` годны, `1–7b` перед `7b` — нет.
  static const String _verseEndRule =
      "CASE WHEN typeof(verse_end) = 'integer' AND verse_end > verse "
      'AND verse_end - verse <= $maxVerseEndSpan '
      "AND (typeof(next) != 'integer' OR verse_end < next "
      'OR (verse_end = next AND part_end < next_part)) '
      'THEN verse_end END';

  // Книга → глава → последний стих, только у книг из [codes]; `verse_end`
  // берётся по правилу [_verseEndRule].
  static Map<int, Map<int, int>> _readLastVerses(
    Database db,
    int version,
    Map<String, int> codes,
  ) {
    final lastVerses = <int, Map<int, int>>{};
    for (final row in db.select(
      'SELECT book, chapter, MAX(COALESCE($_verseEndRule, verse)) '
      'FROM (${_pieces(version)} WHERE chapter >= 1 AND verse >= 1) '
      'GROUP BY book, chapter',
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
