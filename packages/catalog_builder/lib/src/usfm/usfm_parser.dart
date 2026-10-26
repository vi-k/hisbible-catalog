import 'package:catalog_builder/src/usfm/usfm_book.dart';
import 'package:hisbible_format/hisbible_format.dart';

/// Разбирает книгу USFM из eBible.org в стихи, заголовки и сноски.
///
/// Разбор терпим: любой текст разбирается без ошибок. Незнакомый знаковый
/// маркер (у которого в книге есть закрывающий `\xyz*`) оставляет свой
/// текст, незнакомый абзацный работает как `\p`; оба попадают
/// в [UsfmBook.unknownMarkers].
///
/// Заголовок стоит над следующим стихом своей главы и открытого стиха
/// не закрывает: текст после заголовка остаётся в открытом стихе. До первого
/// стиха главы такой текст дописывается к заголовку через пробел. Заголовок
/// без следующего стиха в главе выбрасывается вместе со всем текстом после
/// него до конца главы; текст вне стиха тоже выбрасывается; и то и другое
/// считается в [UsfmBook.droppedFragments]. Исключение — `\sp` (имя
/// говорящего) в конце главы при открытом стихе: выбрасывается и считается
/// только оно само, а текст после него остаётся в стихе. Всё до первой главы,
/// кроме полей книги, выбрасывается и не считается.
UsfmBook parseUsfm(String text) => _Parser(text).parse();

// ---------------------------------------------------------------------------
// Лексер: текст и маркеры.

sealed class _Token {}

final class _Text extends _Token {
  _Text(this.text);

  final String text;
}

final class _Marker extends _Token {
  _Marker(this.name, {required this.closing});

  // Имя без `\`, `+` и `*`.
  final String name;

  // Закрывающий маркер `\name*`.
  final bool closing;
}

// Маркер: `\name`, `\+name`, `\name*`; вехи USFM 3 — `\qt-s`, `\qt-e`.
final _markerPattern = RegExp(
  r'\\\+?([A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)?)(\*?)',
);

List<_Token> _lex(String source) {
  final tokens = <_Token>[];
  var textStart = 0;
  var i = 0;

  void flushText(int end) {
    if (end > textStart) {
      tokens.add(_Text(source.substring(textStart, end)));
    }
  }

  while (true) {
    i = source.indexOf(r'\', i);
    if (i < 0) {
      break;
    }
    flushText(i);
    final match = _markerPattern.matchAsPrefix(source, i);
    if (match == null) {
      // Одинокая косая черта выбрасывается, `\*` — вместе со звёздочкой.
      i = textStart = i + (source.startsWith(r'\*', i) ? 2 : 1);
      continue;
    }
    final name = match[1]!;
    final closing = match[2]!.isNotEmpty;
    var end = match.end;
    if (name.contains('-')) {
      // Веха выбрасывается вместе с атрибутами до `\*`, но не дальше
      // следующего маркера и конца строки: незакрытая веха не съедает текст.
      var stop = source.indexOf(r'\', end);
      final lineEnd = source.indexOf('\n', end);
      if (stop < 0 || (lineEnd >= 0 && lineEnd < stop)) {
        stop = lineEnd < 0 ? source.length : lineEnd;
      } else if (source.startsWith(r'\*', stop)) {
        stop += 2;
      }
      i = textStart = stop;
      continue;
    }
    if (!closing && source.startsWith(r'\*', end)) {
      // Веха без атрибутов: `\ts\*`.
      i = textStart = end + 2;
      continue;
    }
    if (!closing) {
      // Открывающий маркер забирает один пробельный знак за собой.
      if (source.startsWith('\r\n', end)) {
        end += 2;
      } else if (end < source.length && ' \t\r\n'.contains(source[end])) {
        end++;
      }
    }
    tokens.add(_Marker(name, closing: closing));
    i = textStart = end;
  }
  flushText(source.length);
  return tokens;
}

// ---------------------------------------------------------------------------
// Маркеры.

const _styles = {
  'wj': MarkupStyle.wordsOfChrist,
  'add': MarkupStyle.added,
  'nd': MarkupStyle.divineName,
  'em': MarkupStyle.emphasis,
  'it': MarkupStyle.emphasis,
  'qt': MarkupStyle.quote,
};

const _plainMarkers = {
  'bd',
  'bdit',
  'sc',
  'tl',
  'bk',
  'pn',
  'k',
  'qs',
  'jmp',
  'no',
};

const _droppedCharacterMarkers = {'rq', 'va', 'vp', 'ca', 'fig'};

const _noteMarkers = {'f', 'fe', 'ef', 'x', 'ex'};

// Что делает абзацный маркер.
enum _Paragraph {
  // Поле книги до первой главы, после неё выбрасывается.
  field,

  // Выбрасывается с содержимым, не считается.
  silent,

  // Выбрасывается до первой главы, после неё — незнакомый абзацный.
  header,

  chapter,
  verse,

  // Разрыв абзаца.
  paragraph,

  // Продолжение абзаца без разрыва (`\nb`).
  continuation,

  // Строка стихов.
  line,

  // Заголовок над стихом.
  heading,
}

final _numbered = RegExp(r'^(pi|q|qm|li|s|ms|mt|mte)(\d*)$');

// Абзацный маркер [name] и цифра в нём; `null` — маркер незнакомый.
(_Paragraph, int?)? _paragraphOf(String name) {
  switch (name) {
    case 'id' || 'h' || 'toc1' || 'toc2' || 'toc3' || 'cl':
      return (_Paragraph.field, null);
    case 'rem' || 'ide' || 'usfm' || 'sts' || 'mr' || 'sr' || 'r' || 'cp':
      return (_Paragraph.silent, null);
    case 'c':
      return (_Paragraph.chapter, null);
    case 'v':
      return (_Paragraph.verse, null);
    case 'p' || 'm' || 'pm' || 'b':
      return (_Paragraph.paragraph, null);
    case 'nb':
      return (_Paragraph.continuation, null);
    case 'qr' || 'qc':
      return (_Paragraph.line, 0);
    case 'd' || 'sp':
      return (_Paragraph.heading, null);
  }
  final match = _numbered.firstMatch(name);
  if (match != null) {
    final digit = int.tryParse(match[2]!);
    return switch (match[1]!) {
      'pi' => (_Paragraph.paragraph, digit),
      'q' || 'qm' || 'li' => (_Paragraph.line, digit ?? 1),
      's' || 'ms' => (_Paragraph.heading, digit),
      _ => (_Paragraph.header, null),
    };
  }
  if (name.startsWith('i')) {
    return (_Paragraph.header, null);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Сборка разметки одного стиха, заголовка, сноски или поля.

enum _FrameKind { root, style, plain, word, drop }

// Открытый знаковый маркер со своим содержимым.
final class _Frame {
  _Frame(this.kind, this.name, {this.style});

  final _FrameKind kind;
  final String name;
  final MarkupStyle? style;
  final List<MarkupNode> children = [];
  final StringBuffer _text = StringBuffer();

  // Атрибуты после `|`; `null` — их ещё не было.
  StringBuffer? attributes;

  void write(String text) => _text.write(text);

  void add(MarkupNode node) {
    if (node is TextRun) {
      _text.write(node.text);
    } else {
      flush();
      children.add(node);
    }
  }

  // Переносит накопленный текст в узлы; соседний текст склеивается.
  void flush() {
    if (_text.isEmpty) {
      return;
    }
    final text = _text.toString();
    _text.clear();
    if (children.lastOrNull case TextRun(text: final previous)) {
      children.last = TextRun(previous + text);
    } else {
      children.add(TextRun(text));
    }
  }
}

// Разметка со стеком знаковых маркеров и схлопыванием пробелов.
//
// Пробелы в начале срезаются сразу, в конце — в finish и перед разрывом
// строки или абзаца.
final class _Content {
  // [trimStart] — срезать пробелы в начале; текст после заголовка внутри
  // стиха их не срезает: пробел нужен на стыке со стихом.
  _Content({bool trimStart = true}) : _lastSpace = trimStart;

  final List<_Frame> _stack = [_Frame(_FrameKind.root, '')];

  // Последний записанный знак — пробел; в начале считается, что да, если
  // пробелы в начале срезаются.
  bool _lastSpace;

  // Записан текст не из одних пробелов.
  bool hasText = false;

  _Frame get _top => _stack.last;

  // Текст сейчас выбрасывается: открыт выбрасываемый маркер.
  bool get dropping => _top.kind == _FrameKind.drop;

  // Дописывает очищенный текст: пробелы в нём уже схлопнуты.
  void write(String text) {
    if (dropping) {
      return;
    }
    final top = _top;
    var rest = text;
    if (top.kind != _FrameKind.root) {
      if (top.attributes case final attributes?) {
        attributes.write(rest);
        return;
      }
      final bar = rest.indexOf('|');
      if (bar >= 0) {
        top.attributes = StringBuffer(rest.substring(bar + 1));
        rest = rest.substring(0, bar);
      }
    }
    if (_lastSpace && rest.startsWith(' ')) {
      rest = rest.substring(1);
    }
    if (rest.isEmpty) {
      return;
    }
    top.write(rest);
    _lastSpace = rest.endsWith(' ');
    if (_hasNonSpace(rest)) {
      hasText = true;
    }
  }

  // Добавляет знак сноски; пробелов он не меняет.
  void add(MarkupNode node) {
    if (!dropping) {
      _top.add(node);
    }
  }

  // Добавляет разрыв строки или абзаца, срезав пробелы перед ним.
  void addBreak(MarkupNode node) {
    if (dropping) {
      return;
    }
    final top = _top..flush();
    final trimmed = _trimEnd(top.children).nodes;
    top.children
      ..clear()
      ..addAll(trimmed)
      ..add(node);
    _lastSpace = true;
  }

  // Открывает знаковый маркер; внутри выбрасываемого всё выбрасывается.
  void open(_FrameKind kind, String name, {MarkupStyle? style}) {
    _top.flush();
    _stack.add(_Frame(dropping ? _FrameKind.drop : kind, name, style: style));
  }

  // Закрывает маркер [name] и всё, что открыто внутри него; `false` —
  // такой маркер не открыт.
  bool close(String name) {
    final index = _stack.lastIndexWhere((frame) => frame.name == name);
    if (index <= 0) {
      return false;
    }
    while (_stack.length > index) {
      _closeTop();
    }
    return true;
  }

  // Закрывает все маркеры и возвращает их по порядку открытия.
  List<_Frame> closeAll() {
    final open = _stack.sublist(1);
    while (_stack.length > 1) {
      _closeTop();
    }
    return open;
  }

  // Снова открывает маркеры, перенесённые из прошлого стиха; слово
  // со Стронгом не переносится.
  void reopen(List<_Frame> frames) {
    for (final frame in frames) {
      if (frame.kind != _FrameKind.word) {
        open(frame.kind, frame.name, style: frame.style);
      }
    }
  }

  // Дописывает в конец разметку [tail]: текст на стыке отделяется одним
  // пробелом, знак сноски на стыке прилегает к слову перед ним.
  //
  // Знаки сносок получают новые номера и знаки по [refs].
  void append(_Content tail, {Map<int, FootnoteRef> refs = const {}}) {
    tail.closeAll();
    final tailRoot = tail._top..flush();
    final nodes = refs.isEmpty
        ? [...tailRoot.children]
        : _renumber(tailRoot.children, refs);
    if (nodes case [TextRun(:final text), ...] when text.startsWith(' ')) {
      if (_lastSpace) {
        final rest = text.substring(1);
        if (rest.isEmpty) {
          nodes.removeAt(0);
        } else {
          nodes[0] = TextRun(rest);
        }
      }
    } else if (nodes.isNotEmpty &&
        !_lastSpace &&
        nodes.first is! LineBreak &&
        nodes.first is! ParagraphBreak &&
        nodes.first is! FootnoteRef) {
      nodes.insert(0, const TextRun(' '));
    }
    if (nodes.isEmpty) {
      return;
    }
    closeAll();
    final root = _top..flush();
    for (final node in nodes) {
      if (node is LineBreak || node is ParagraphBreak) {
        addBreak(node);
      } else {
        root.add(node);
      }
    }
    _lastSpace = tail._lastSpace;
    hasText = hasText || tail.hasText;
  }

  // Закрывает всё и отдаёт разметку без пробелов в конце.
  List<MarkupNode> finish() {
    closeAll();
    final root = _top..flush();
    return _trimEnd(root.children).nodes;
  }

  void _closeTop() {
    final frame = _stack.removeLast()..flush();
    final parent = _top;
    final children = frame.children;
    switch (frame.kind) {
      case _FrameKind.root || _FrameKind.drop:
        break;
      case _FrameKind.plain:
        children.forEach(parent.add);
      case _FrameKind.style:
        if (children.isNotEmpty) {
          parent.add(StyledSpan(frame.style!, children));
        }
      case _FrameKind.word:
        final (:strong, :morph) = _wordAttributes(
          frame.attributes?.toString() ?? '',
        );
        if (strong.isEmpty && morph == null) {
          children.forEach(parent.add);
        } else if (children.isNotEmpty) {
          parent.add(TaggedWord(children, strong: strong, morph: morph));
        }
    }
  }
}

final _attributePattern = RegExp(r'([\w-]+)\s*=\s*"([^"]*)"');
final _strongSeparator = RegExp(r'[,\s]+');
final _strongZeros = RegExp(r'^([A-Za-z]+)0+(?=\d)');

// Номера Стронга и морфология из атрибутов `\w`; нули после буквы
// срезаются: `H0430` — `H430`.
({List<String> strong, String? morph}) _wordAttributes(String attributes) {
  var strong = <String>[];
  String? morph;
  for (final match in _attributePattern.allMatches(attributes)) {
    final value = match[2]!.trim();
    switch (match[1]) {
      case 'strong':
        strong = [
          for (final number in value.split(_strongSeparator))
            if (number.isNotEmpty)
              number.replaceFirstMapped(_strongZeros, (m) => m[1]!),
        ];
      case 'x-morph':
        if (value.isNotEmpty) {
          morph = value;
        }
    }
  }
  return (strong: strong, morph: morph);
}

// Меняет знаки сносок по [refs] (по старому номеру), заходя внутрь стилей
// и слов.
List<MarkupNode> _renumber(
  List<MarkupNode> nodes,
  Map<int, FootnoteRef> refs,
) => [
  for (final node in nodes)
    switch (node) {
      FootnoteRef(:final id) => refs[id] ?? node,
      StyledSpan(:final style, :final children) => StyledSpan(
        style,
        _renumber(children, refs),
      ),
      TaggedWord(:final children, :final strong, :final morph) => TaggedWord(
        _renumber(children, refs),
        strong: strong,
        morph: morph,
      ),
      _ => node,
    },
];

// Срезает пробелы в конце разметки, заходя внутрь стилей и слов.
//
// Знаки сносок остаются на месте, пробелы перед ними срезаются. `done` —
// встретился текст или разрыв, дальше влево резать нечего.
({List<MarkupNode> nodes, bool done}) _trimEnd(List<MarkupNode> nodes) {
  final out = [...nodes];
  for (var i = out.length - 1; i >= 0; i--) {
    switch (out[i]) {
      case FootnoteRef():
        continue;
      case LineBreak() || ParagraphBreak():
        return (nodes: out, done: true);
      case TextRun(:final text):
        final trimmed = _trimRightSpaces(text);
        if (trimmed.isEmpty) {
          out.removeAt(i);
          continue;
        }
        out[i] = TextRun(trimmed);
        return (nodes: out, done: true);
      case StyledSpan(:final style, :final children):
        final inner = _trimEnd(children);
        if (inner.nodes.isEmpty) {
          out.removeAt(i);
        } else {
          out[i] = StyledSpan(style, inner.nodes);
        }
        if (inner.done) {
          return (nodes: out, done: true);
        }
      case TaggedWord(:final children, :final strong, :final morph):
        final inner = _trimEnd(children);
        if (inner.nodes.isEmpty) {
          out.removeAt(i);
        } else {
          out[i] = TaggedWord(inner.nodes, strong: strong, morph: morph);
        }
        if (inner.done) {
          return (nodes: out, done: true);
        }
    }
  }
  return (nodes: out, done: false);
}

String _trimRightSpaces(String text) {
  var end = text.length;
  while (end > 0 && text.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return text.substring(0, end);
}

bool _hasNonSpace(String text) => text.replaceAll(' ', '').isNotEmpty;

final _spaces = RegExp(r'[ \t\r\n\f\v]+');

// Убирает `¶` и `//`, схлопывает пробелы, `~` делает неразрывным пробелом.
String _clean(String text) => text
    .replaceAll('¶', '')
    .replaceAll('//', '')
    .replaceAll(_spaces, ' ')
    .replaceAll('~', ' ');

// ---------------------------------------------------------------------------
// Разбор книги.

// Куда идёт текст абзаца.
enum _Target { verse, heading, drop, silent, field }

final class _VerseBuilder {
  _VerseBuilder(this.chapter, this.verse, this.verseEnd);

  final int chapter;
  final int verse;
  int? verseEnd;
  final _Content content = _Content();
}

final class _HeadingBuilder {
  _HeadingBuilder(
    this.chapter,
    this.kind,
    this.level,
    this.firstNote, {
    required this.speaker,
  });

  final int chapter;
  final HeadingKind kind;
  final int level;

  // Имя говорящего (`\sp`).
  final bool speaker;

  // Сколько сносок было до заголовка: к стольким откатываются, если
  // заголовок выброшен.
  final int firstNote;
  final _Content content = _Content();
  final List<_NoteBuilder> notes = [];

  // Стих под заголовком; `null` — стиха ещё не было.
  int? verse;

  // Текст открытого стиха после заголовка до следующего заголовка;
  // дописывается к стиху на следующем `\v`.
  _Content? tail;
}

final class _NoteBuilder {
  _NoteBuilder({
    required this.id,
    required this.chapter,
    required this.verse,
    required this.kind,
    required this.caller,
    required this.auto,
    required this.nodes,
  });

  int id;
  final int chapter;
  int? verse;
  final FootnoteKind kind;
  String caller;

  // Знак дан по порядку в главе (`+`).
  final bool auto;
  final List<MarkupNode> nodes;
}

// Открытая сноска: `\f`, `\fe`, `\ef`, `\x` или `\ex`.
final class _OpenNote {
  _OpenNote(this.name, {required this.keep});

  final String name;

  // Сноска остаётся в книге: она в стихе или заголовке.
  final bool keep;
  final _Content content = _Content();

  // Знак сноски как в тексте; `null` — ещё не прочитан.
  String? caller;

  bool get _crossref => name.endsWith('x');

  FootnoteKind get kind =>
      _crossref ? FootnoteKind.crossref : FootnoteKind.note;

  // Маркер — часть сноски: `\ft`, `\fq`, `\xo`, `\xt` и прочие; части
  // ссылки бывают и в примечании, и наоборот.
  bool hasPart(String marker) =>
      marker.length > 1 &&
      (marker[0] == 'f' || marker[0] == 'x') &&
      !_noteMarkers.contains(marker) &&
      marker != 'fig' &&
      _lowercase.hasMatch(marker);
}

final _lowercase = RegExp(r'^[a-z]+$');
final _verseNumber = RegExp(r'(\d+)[a-z]?(?:[-–](\d+)[a-z]?)?');
final _leadingDigits = RegExp(r'^\d+');
final _whitespace = RegExp(r'\s');

final class _Parser {
  _Parser(String source) : _tokens = _lex(source) {
    for (final token in _tokens) {
      if (token case _Marker(:final name, closing: true)) {
        _closedNames.add(name);
      }
    }
  }

  final List<_Token> _tokens;

  // Маркеры, у которых в книге есть закрывающий: так незнакомый знаковый
  // отличается от незнакомого абзацного.
  final Set<String> _closedNames = {};

  final Map<String, String> _fields = {};
  final List<_VerseBuilder> _verses = [];
  final List<_HeadingBuilder> _headings = [];
  final List<_HeadingBuilder> _pendingHeadings = [];
  final List<_NoteBuilder> _notes = [];
  final List<MarkupNode> _breaks = [];
  final Set<String> _unknown = {};
  int _dropped = 0;

  _Target _targetKind = _Target.silent;
  _Content _target = _Content();
  late String _field;
  _HeadingBuilder? _heading;
  _OpenNote? _note;

  // Ждём номер главы или стиха в следующем тексте.
  _Paragraph? _awaitNumber;

  // Маркеры, открытые в конце прошлого стиха: продолжаются в следующем.
  List<_Frame> _carried = [];

  bool _inChapters = false;
  int _chapter = 0;
  bool _chapterHasVerse = false;
  _VerseBuilder? _verse;

  int _callers = 0;

  _Content get _current => _note?.content ?? _target;

  // Текст сейчас идёт в стих, а не в сноску.
  bool get _inVerse => _note == null && _targetKind == _Target.verse;

  UsfmBook parse() {
    for (final token in _tokens) {
      switch (token) {
        case _Text(:final text):
          _text(text);
        case _Marker(:final name, closing: true):
          _closeMarker(name);
        case _Marker(:final name):
          _openMarker(name);
      }
    }
    _resolvePending();
    _endChapter();

    String? field(String name) {
      final value = _fields[name];
      return value == null || value.isEmpty ? null : value;
    }

    return UsfmBook(
      code: _fields['id']?.split(_whitespace).first ?? '',
      header: field('h'),
      toc1: field('toc1'),
      toc2: field('toc2'),
      toc3: field('toc3'),
      chapterLabel: field('cl'),
      verses: [
        for (final verse in _verses)
          UsfmVerse(
            chapter: verse.chapter,
            verse: verse.verse,
            verseEnd: verse.verseEnd,
            nodes: verse.content.finish(),
          ),
      ],
      headings: [
        for (final heading in _headings)
          if (heading.content.finish() case final nodes when nodes.isNotEmpty)
            UsfmHeading(
              chapter: heading.chapter,
              verse: heading.verse ?? 0,
              kind: heading.kind,
              level: heading.level,
              nodes: nodes,
            ),
      ],
      notes: [
        for (final note in _notes)
          UsfmNote(
            id: note.id,
            chapter: note.chapter,
            verse: note.verse ?? 0,
            kind: note.kind,
            caller: note.caller,
            nodes: note.nodes,
          ),
      ],
      droppedFragments: _dropped,
      unknownMarkers: _unknown,
    );
  }

  void _text(String raw) {
    var text = raw;
    if (_awaitNumber != null) {
      final (word, rest) = _firstWord(text);
      if (word.isEmpty) {
        return;
      }
      _takeNumber(word);
      text = rest;
    }
    final note = _note;
    if (note != null && note.caller == null) {
      final (word, rest) = _firstWord(text);
      if (word.isEmpty) {
        return;
      }
      note.caller = word;
      text = rest;
    }
    final cleaned = _clean(text);
    if (cleaned.isEmpty) {
      return;
    }
    if (_inVerse && !_target.dropping && _hasNonSpace(cleaned)) {
      _flushBreaks();
    }
    _current.write(cleaned);
  }

  void _openMarker(String name) {
    _resolvePending();
    if (_noteMarkers.contains(name)) {
      if (_note != null) {
        _closeNote();
      }
      _openNote(name);
      return;
    }
    final note = _note;
    if (note != null && note.hasPart(name)) {
      // Часть сноски тянется до следующей части или до конца сноски.
      note.content.closeAll();
      switch (name) {
        case 'fr' || 'xo':
          note.content.open(_FrameKind.drop, name);
        case 'fq' || 'fqa' || 'fk':
          note.content.open(
            _FrameKind.style,
            name,
            style: MarkupStyle.emphasis,
          );
        default:
          note.content.open(_FrameKind.plain, name);
      }
      return;
    }
    if (_styles[name] case final style?) {
      _openCharacter(_FrameKind.style, name, style: style);
      return;
    }
    if (name == 'w') {
      _openCharacter(_FrameKind.word, name);
      return;
    }
    if (_plainMarkers.contains(name)) {
      _openCharacter(_FrameKind.plain, name);
      return;
    }
    if (_droppedCharacterMarkers.contains(name)) {
      _openCharacter(_FrameKind.drop, name);
      return;
    }
    final paragraph = _paragraphOf(name);
    if (paragraph == null && _closedNames.contains(name)) {
      _unknown.add(name);
      _openCharacter(_FrameKind.plain, name);
      return;
    }
    if (note != null && paragraph == null) {
      // Незнакомый маркер внутри сноски — её часть с простым текстом,
      // а не абзац: текст сноски не уходит в стих.
      _unknown.add(name);
      note.content
        ..closeAll()
        ..open(_FrameKind.plain, name);
      return;
    }
    if (_note != null) {
      _closeNote();
    }
    _paragraph(name, paragraph);
  }

  void _openCharacter(_FrameKind kind, String name, {MarkupStyle? style}) {
    if (_inVerse && kind != _FrameKind.drop && !_target.dropping) {
      _flushBreaks();
    }
    _current.open(kind, name, style: style);
  }

  void _closeMarker(String name) {
    _resolvePending();
    final note = _note;
    if (note == null) {
      // Лишний закрывающий пропускается.
      _target.close(name);
    } else if (name == note.name) {
      _closeNote();
    } else {
      note.content.close(name);
    }
  }

  void _paragraph(String name, (_Paragraph, int?)? rule) {
    if (rule == null) {
      _unknown.add(name);
    }
    final (kind, digit) = rule ?? (_Paragraph.paragraph, null);
    switch (kind) {
      case _Paragraph.field when !_inChapters:
        _setTarget(_Target.field);
        _field = name;
      case _Paragraph.field || _Paragraph.silent:
        _setTarget(_Target.silent);
      case _Paragraph.header when !_inChapters:
        _setTarget(_Target.silent);
      case _Paragraph.header:
        _unknown.add(name);
        _breakParagraph(const ParagraphBreak());
      case _Paragraph.chapter:
        _endChapter();
        _awaitNumber = _Paragraph.chapter;
      case _Paragraph.verse:
        _carried = _targetKind == _Target.verse ? _target.closeAll() : [];
        _awaitNumber = _Paragraph.verse;
      case _Paragraph.paragraph:
        _breakParagraph(const ParagraphBreak());
      case _Paragraph.line:
        _breakParagraph(LineBreak(indent: digit ?? 1));
      case _Paragraph.continuation:
        _continueParagraph();
      case _Paragraph.heading when !_inChapters:
        _setTarget(_Target.silent);
      case _Paragraph.heading:
        final (headingKind, level) = switch (name) {
          'd' => (HeadingKind.title, 1),
          'sp' => (HeadingKind.section, 3),
          _ when name.startsWith('ms') => (HeadingKind.major, digit ?? 1),
          _ => (HeadingKind.section, digit ?? 1),
        };
        final heading = _HeadingBuilder(
          _chapter,
          headingKind,
          // Уровень формата — 1..3: `\s4` и `\ms9` — третий, `\s0` — первый.
          level.clamp(1, 3),
          _notes.length,
          speaker: name == 'sp',
        );
        _pendingHeadings.add(heading);
        _setTarget(_Target.heading, heading.content);
        _heading = heading;
    }
  }

  // Куда идёт текст нового абзаца.
  void _continueParagraph() {
    final verse = _verse;
    final heading = _pendingHeadings.lastOrNull;
    if (!_inChapters) {
      // Вступление до первой главы.
      _setTarget(_Target.silent);
    } else if (verse != null && heading == null) {
      _setTarget(_Target.verse, verse.content);
    } else if (verse != null && heading != null) {
      // Текст после заголовка внутри стиха ждёт следующего `\v`: без него
      // он выбрасывается вместе с заголовком.
      _setTarget(_Target.verse, heading.tail ??= _Content(trimStart: false));
    } else if (heading != null) {
      // До первого стиха главы текст дописывается к заголовку.
      _setTarget(_Target.heading, heading.content);
      heading.content.write(' ');
    } else {
      _setTarget(_Target.drop);
    }
  }

  void _breakParagraph(MarkupNode node) {
    _continueParagraph();
    if (!_inChapters) {
      return;
    }
    if (node is ParagraphBreak) {
      // Разрыв абзаца заменяет пустые строки перед собой, а в начале главы
      // ничего не даёт.
      _breaks.clear();
      if (_chapterHasVerse) {
        _breaks.add(node);
      }
    } else if (_breaks.isNotEmpty && _breaks.last is LineBreak) {
      _breaks.last = node;
    } else {
      _breaks.add(node);
    }
  }

  void _flushBreaks() {
    for (final node in _breaks) {
      _target.addBreak(node);
    }
    _breaks.clear();
  }

  void _setTarget(_Target kind, [_Content? content]) {
    switch (_targetKind) {
      case _Target.drop:
        _target.closeAll();
        if (_target.hasText) {
          _dropped++;
        }
      case _Target.field:
        _fields[_field] = plainText(_target.finish()).trim();
      case _Target.verse || _Target.heading:
        _target.closeAll();
      case _Target.silent:
        break;
    }
    _targetKind = kind;
    _target = content ?? _Content();
  }

  void _resolvePending() {
    if (_awaitNumber != null) {
      _takeNumber('');
    }
    final note = _note;
    if (note != null && note.caller == null) {
      note.caller = '+';
    }
  }

  void _takeNumber(String number) {
    final which = _awaitNumber;
    _awaitNumber = null;
    if (which == _Paragraph.chapter) {
      final parsed = int.tryParse(_leadingDigits.stringMatch(number) ?? '');
      _chapter = parsed ?? _chapter + 1;
      _inChapters = true;
    } else {
      _startVerse(number);
    }
  }

  void _startVerse(String number) {
    final carried = _carried;
    _carried = [];
    if (!_inChapters) {
      _setTarget(_Target.silent);
      return;
    }
    final match = _verseNumber.matchAsPrefix(number);
    final parsed = match == null ? null : int.tryParse(match[1]!);
    if (match != null && parsed == null) {
      // Номер не помещается в `int`: маркер выбрасывается, текст остаётся
      // в открытом стихе вместе с его незакрытыми стилями.
      if (_targetKind == _Target.verse) {
        _target.reopen(carried);
      }
      return;
    }
    for (final heading in _pendingHeadings) {
      if (heading.tail case final tail?) {
        _verse?.content.append(tail);
      }
    }
    final last = _verses.lastOrNull;
    final lastInChapter = last != null && last.chapter == _chapter
        ? last
        : null;
    final verseNumber = parsed ?? (lastInChapter?.verse ?? 0) + 1;
    // Конец, который не помещается в `int`, отбрасывается.
    final rangeEnd = match?[2] == null ? null : int.tryParse(match![2]!);
    final end = rangeEnd != null && rangeEnd > verseNumber ? rangeEnd : null;
    final _VerseBuilder verse;
    if (lastInChapter != null && lastInChapter.verse == verseNumber) {
      // `\v 1b` дописывается к стиху 1.
      verse = lastInChapter;
      if (end != null && end > (verse.verseEnd ?? 0)) {
        verse.verseEnd = end;
      }
    } else {
      verse = _VerseBuilder(_chapter, verseNumber, end);
      _verses.add(verse);
    }
    _chapterHasVerse = true;
    for (final heading in _pendingHeadings) {
      heading.verse = verseNumber;
      for (final note in heading.notes) {
        note.verse = verseNumber;
      }
      _headings.add(heading);
    }
    _pendingHeadings.clear();
    _setTarget(_Target.verse, verse.content);
    _verse = verse;
    verse.content.reopen(carried);
  }

  void _endChapter() {
    if (_note != null) {
      _closeNote();
    }
    _carried = [];
    _setTarget(_Target.drop);
    if (_pendingHeadings.isNotEmpty) {
      _dropPendingHeadings();
    }
    _breaks.clear();
    _verse = null;
    _heading = null;
    _chapterHasVerse = false;
    _callers = 0;
  }

  // Заголовки без стиха в конце главы выбрасываются вместе с текстом
  // после них и со всеми их сносками. Исключение — `\sp` в открытом стихе
  // до первого другого заголовка: выбрасывается только имя говорящего,
  // текст после него остаётся в стихе.
  void _dropPendingHeadings() {
    final pending = [..._pendingHeadings];
    _pendingHeadings.clear();
    final verse = _verse;
    var labels = 0;
    if (verse != null) {
      while (labels < pending.length && pending[labels].speaker) {
        labels++;
      }
    }
    final removed = <_NoteBuilder>{};
    for (final (index, heading) in pending.indexed) {
      if (heading.content.finish().isNotEmpty) {
        _dropped++;
      }
      removed.addAll(heading.notes);
      if (index >= labels) {
        final tail = heading.tail?..closeAll();
        if (tail != null && tail.hasText) {
          _dropped++;
        }
      }
    }
    if (labels < pending.length) {
      // Сноски выброшенного текста — последние в книге.
      removed.addAll(_notes.skip(pending[labels].firstNote));
    }
    final refs = <int, FootnoteRef>{};
    if (removed.isNotEmpty) {
      // Номера сносок идут подряд, знаки `+` — по порядку в главе:
      // оставшиеся после выброшенных сдвигаются.
      _notes.removeWhere(removed.contains);
      _callers = 0;
      for (final (index, note) in _notes.indexed) {
        final id = index + 1;
        var caller = note.caller;
        if (note.chapter == _chapter && note.auto) {
          caller = _autoCaller(_callers++);
        }
        if (note.id != id || note.caller != caller) {
          refs[note.id] = FootnoteRef(id, caller);
          note
            ..id = id
            ..caller = caller;
        }
      }
    }
    for (final heading in pending.take(labels)) {
      if (heading.tail case final tail?) {
        verse?.content.append(tail, refs: refs);
      }
    }
  }

  void _openNote(String name) {
    final keep =
        (_targetKind == _Target.verse || _targetKind == _Target.heading) &&
        !_target.dropping;
    if (keep && _targetKind == _Target.verse) {
      _flushBreaks();
    }
    _note = _OpenNote(name, keep: keep);
  }

  void _closeNote() {
    final note = _note!;
    _note = null;
    if (!note.keep) {
      return;
    }
    final raw = note.caller ?? '+';
    final caller = switch (raw) {
      '+' => _autoCaller(_callers++),
      '-' => '',
      _ => raw,
    };
    final id = _notes.length + 1;
    final builder = _NoteBuilder(
      id: id,
      chapter: _chapter,
      verse: _targetKind == _Target.verse ? _verse?.verse : null,
      kind: note.kind,
      caller: caller,
      auto: raw == '+',
      nodes: note.content.finish(),
    );
    if (_targetKind == _Target.heading) {
      _heading?.notes.add(builder);
    }
    _notes.add(builder);
    _target.add(FootnoteRef(id, caller));
  }
}

// Первое слово текста и остаток после него.
(String, String) _firstWord(String text) {
  final trimmed = text.trimLeft();
  final end = trimmed.indexOf(_whitespace);
  return end < 0
      ? (trimmed, '')
      : (trimmed.substring(0, end), trimmed.substring(end));
}

// Знак сноски `+` по порядку в главе: `a`…`z`, `aa`, `ab`…
String _autoCaller(int index) {
  final codes = <int>[];
  var n = index + 1;
  while (n > 0) {
    n--;
    codes.insert(0, 0x61 + n % 26);
    n ~/= 26;
  }
  return String.fromCharCodes(codes);
}
