import 'package:hisbible_format/hisbible_format.dart';

/// Названия книг для разбора ссылок в тексте `\xt`: имя → номер книги
/// справочника.
///
/// Имена сравниваются без учёта регистра, без точки на конце и без
/// различия пробела и неразрывного пробела; имя с пробелами узнаётся
/// и без них (`1 Кор` и `1Кор`).
final class RefBooks {
  /// Создаёт список из [names]: имя → номер книги.
  RefBooks(Map<String, int> names) : _names = _normalized(names) {
    _longestFirst = _names.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  /// Список имён книг модуля: короткое, полное и строки `\toc2`, `\toc3`.
  RefBooks.of(
    Iterable<
      ({
        int number,
        String shortName,
        String longName,
        String? toc2,
        String? toc3,
      })
    >
    books,
  ) : this(_namesOf(books));

  final Map<String, int> _names;

  // Нормализованные имена от длинных к коротким: так самое длинное
  // совпадение начала находится первым.
  late final List<String> _longestFirst;

  /// Номер книги по имени [name] или `null`.
  int? book(String name) => _names[_normalize(name)];

  /// Книга, имя которой стоит в [text] с позиции [start]: самое длинное
  /// совпадение, после которого не идёт буква. `end` в ответе — позиция
  /// сразу за именем; необязательная точка за ним не входит.
  ({int book, int end})? matchAt(String text, int start) {
    for (final name in _longestFirst) {
      final end = start + name.length;
      if (end > text.length) {
        continue;
      }
      final candidate = text
          .substring(start, end)
          .replaceAll(_nonBreaking, ' ')
          .toLowerCase();
      if (candidate != name) {
        continue;
      }
      if (end < text.length && _letter.hasMatch(text[end])) {
        continue;
      }

      return (book: _names[name]!, end: end);
    }

    return null;
  }
}

/// Сколько `\xt` стало ссылками: счётчики к [resolveXtLinks].
final class XtStats {
  /// `\xt`, в которых есть хотя бы одна ссылка, в том числе по `link-href`.
  int linked = 0;

  /// `\xt` с местом из `link-href`.
  int byHref = 0;

  /// `\xt`, из текста которых не вышло ни одной ссылки.
  int unresolved = 0;
}

// Имя → номер книги по всем названиям [books].
Map<String, int> _namesOf(
  Iterable<
    ({
      int number,
      String shortName,
      String longName,
      String? toc2,
      String? toc3,
    })
  >
  books,
) {
  final names = <String, int>{};
  for (final book in books) {
    for (final name in [book.shortName, book.longName, book.toc2, book.toc3]) {
      if (name != null && name.trim().isNotEmpty) {
        names.putIfAbsent(name, () => book.number);
      }
    }
  }

  return names;
}

final _nonBreaking = RegExp(' ');
final _letter = RegExp(r'\p{L}', unicode: true);
final _spaces = RegExp(r'\s+');

String _normalize(String name) {
  var text = name.replaceAll(_spaces, ' ').trim().toLowerCase();
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1).trimRight();
  }

  return text;
}

// Нормализует имена и добавляет к каждому с пробелами вариант без них.
Map<String, int> _normalized(Map<String, int> names) {
  final out = <String, int>{};
  for (final MapEntry(:key, :value) in names.entries) {
    final name = _normalize(key);
    if (name.isEmpty) {
      continue;
    }
    out.putIfAbsent(name, () => value);
    if (name.contains(' ')) {
      out.putIfAbsent(name.replaceAll(' ', ''), () => value);
    }
  }

  return out;
}

/// Заменяет `CrossrefLink(null, …)` ссылками, разобранными из текста,
/// остальные узлы не трогает.
///
/// [book] и [chapter] — книга и глава сноски. Текст `\xt` делится по `;`;
/// кусок — `[Книга] Г:С[-С|-Г:С]`, после запятой в куске — `С[-С]` той же
/// главы или `Г:С`. Кусок без книги берёт книгу прошлого куска того же
/// `\xt`, а первый — [book]. Одинокий номер стиха без книги и главы
/// остаётся текстом, поэтому [chapter] пока не нужна. Не разобранное
/// остаётся текстом; в ссылку идёт всё место вместе с названием книги,
/// знаки между местами остаются снаружи.
///
/// [exists] проверяет место по схеме книги модуля: `false` — место
/// остаётся текстом; без него места не проверяются. Места из `link-href`
/// не проверяются. Счётчики пишутся в [stats].
List<MarkupNode> resolveXtLinks(
  List<MarkupNode> nodes,
  RefBooks books, {
  required int book,
  required int chapter,
  bool Function(RefRange place)? exists,
  XtStats? stats,
}) => [
  for (final node in nodes) ..._resolveNode(node, books, book, exists, stats),
];

List<MarkupNode> _resolveNode(
  MarkupNode node,
  RefBooks books,
  int book,
  bool Function(RefRange place)? exists,
  XtStats? stats,
) {
  List<MarkupNode> walk(List<MarkupNode> children) => [
    for (final child in children)
      ..._resolveNode(child, books, book, exists, stats),
  ];

  switch (node) {
    case CrossrefLink(target: null, :final children):
      if (children.every((child) => child is TextRun)) {
        final text = children.map((child) => (child as TextRun).text).join();
        final (:nodes, :links) = _scan(text, books, book, exists);
        if (links > 0) {
          stats?.linked++;

          return nodes;
        }
      }
      stats?.unresolved++;

      return children;
    case CrossrefLink(:final children):
      stats
        ?..linked += 1
        ..byHref += 1;

      return [CrossrefLink(node.target, walk(children))];
    case StyledSpan(:final style, :final children):
      return [StyledSpan(style, walk(children))];
    case TaggedWord(:final children, :final strong, :final morph):
      return [TaggedWord(walk(children), strong: strong, morph: morph)];
    case TextRun() || FootnoteRef() || LineBreak() || ParagraphBreak():
      return [node];
  }
}

// Глава и стих: `3:16`, с буквой части стиха после номера.
const _letterPart = r'(?:[a-zа-я](?![\p{L}\d]))?';
final _chapterVerse = RegExp(
  r'(\d{1,4}):(\d{1,4})(?!\d)'
  '$_letterPart'
  r'(?:\s*[-–—]\s*(\d{1,4})(?!\d)(?::(\d{1,4})(?!\d))?'
  '$_letterPart)?',
  unicode: true,
);
final _wordAfter = RegExp(r'\s+\p{L}', unicode: true);
final _verseOnly = RegExp(
  r'(\d{1,4})(?![\d:])'
  '$_letterPart'
  r'(?:\s*[-–—]\s*(\d{1,4})(?![\d:])'
  '$_letterPart)?',
  unicode: true,
);

// Разобранное место: оно же, позиция за ним, книга и глава для
// следующего.
typedef _Place = ({RefRange range, int end, int book, int chapter});

({List<MarkupNode> nodes, int links}) _scan(
  String text,
  RefBooks books,
  int initialBook,
  bool Function(RefRange place)? exists,
) {
  final nodes = <MarkupNode>[];
  var cursor = 0;
  var links = 0;
  var book = initialBook;
  var chapter = 0;

  // Разобрать место с позиции [at]: сначала с названием книги или с
  // главой и стихом в книге [book], потом, если [verseToo], одним стихом
  // главы [chapter].
  _Place? placeAt(int at, {required bool verseToo}) {
    return _withBook(text, at, books, exists) ??
        _withoutBook(text, at, book, exists) ??
        (verseToo ? _verseInChapter(text, at, book, chapter, exists) : null);
  }

  void take(_Place place, int start) {
    if (cursor < start) {
      nodes.add(TextRun(text.substring(cursor, start)));
    }
    nodes.add(
      CrossrefLink(place.range, [TextRun(text.substring(start, place.end))]),
    );
    cursor = place.end;
    links++;
    book = place.book;
    chapter = place.chapter;
  }

  var pos = 0;
  while (pos < text.length) {
    final start = _skipSpaces(text, pos);
    if (placeAt(start, verseToo: false) case final first?) {
      take(first, start);
      pos = first.end;
      while (true) {
        final comma = _skipSpaces(text, pos);
        if (comma >= text.length || text[comma] != ',') {
          break;
        }
        final next = _skipSpaces(text, comma + 1);
        final place = placeAt(next, verseToo: true);
        if (place == null) {
          break;
        }
        take(place, next);
        pos = place.end;
      }
    }
    // Остаток куска до `;` — текст.
    final semicolon = text.indexOf(';', pos);
    if (semicolon < 0) {
      break;
    }
    pos = semicolon + 1;
  }
  if (cursor < text.length) {
    nodes.add(TextRun(text.substring(cursor)));
  }

  return (nodes: nodes, links: links);
}

int _skipSpaces(String text, int from) {
  var i = from;
  while (i < text.length && _spaces.hasMatch(text[i])) {
    i++;
  }

  return i;
}

// `Книга Г:С…`: после названия — необязательная точка и пробелы.
_Place? _withBook(
  String text,
  int at,
  RefBooks books,
  bool Function(RefRange place)? exists,
) {
  final found = books.matchAt(text, at);
  if (found == null) {
    return null;
  }
  var i = found.end;
  if (i < text.length && text[i] == '.') {
    i++;
  }

  return _withoutBook(text, _skipSpaces(text, i), found.book, exists);
}

// `Г:С[-С|-Г:С]` в книге [book].
_Place? _withoutBook(
  String text,
  int at,
  int book,
  bool Function(RefRange place)? exists,
) {
  final match = _chapterVerse.matchAsPrefix(text, at);
  if (match == null) {
    return null;
  }
  final chapter = int.parse(match[1]!);
  final verse = int.parse(match[2]!);
  final first = match[3] == null ? null : int.parse(match[3]!);
  final second = match[4] == null ? null : int.parse(match[4]!);
  // `-С` — стих той же главы, `-Г:С` — глава и стих.
  final (int endChapter, int? endVerse) = switch ((first, second)) {
    (final c?, final v?) => (c, v),
    (final v?, null) => (chapter, v),
    _ => (chapter, null),
  };

  return _place(
    book,
    (chapter, verse),
    (endChapter, endVerse),
    end: match.end,
    exists: exists,
  );
}

// `С[-С]` в главе [chapter] книги [book]; без прошлого места — `null`.
_Place? _verseInChapter(
  String text,
  int at,
  int book,
  int chapter,
  bool Function(RefRange place)? exists,
) {
  if (chapter == 0) {
    return null;
  }
  final match = _verseOnly.matchAsPrefix(text, at);
  // Номер, за которым идёт слово, — начало названия книги (`2 Kings`),
  // а не стих.
  if (match == null || _wordAfter.matchAsPrefix(text, match.end) != null) {
    return null;
  }

  return _place(
    book,
    (chapter, int.parse(match[1]!)),
    (chapter, match[2] == null ? null : int.parse(match[2]!)),
    end: match.end,
    exists: exists,
  );
}

// Собирает место и проверяет границы и [exists]; `null` — не годится.
// Конец раньше начала или за границами формата — место не годится целиком.
_Place? _place(
  int book,
  (int, int) start,
  (int, int?) last, {
  required int end,
  required bool Function(RefRange place)? exists,
}) {
  bool inBounds(int chapter, int verse) =>
      chapter >= 1 &&
      chapter <= maxChapterNumber &&
      verse >= 1 &&
      verse <= maxVerseNumber;
  final (chapter, verse) = start;
  if (!inBounds(chapter, verse)) {
    return null;
  }
  final (endChapter, endVerse) = last;
  VerseRef? endRef;
  if (endVerse != null) {
    if (!inBounds(endChapter, endVerse) ||
        endChapter < chapter ||
        (endChapter == chapter && endVerse <= verse)) {
      return null;
    }
    endRef = VerseRef(book, endChapter, endVerse);
  }
  final range = RefRange(VerseRef(book, chapter, verse), endRef);
  if (exists != null && !exists(range)) {
    return null;
  }

  return (
    range: range,
    end: end,
    book: book,
    chapter: endRef?.chapter ?? chapter,
  );
}
