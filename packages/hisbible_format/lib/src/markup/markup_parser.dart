import 'package:hisbible_format/src/markup/markup_node.dart';
import 'package:hisbible_format/src/markup/markup_writer.dart';
import 'package:hisbible_format/src/refs/ref_range.dart';

/// Разбирает разметку модуля в дерево узлов.
///
/// Читатель терпим: незнакомый тег выбрасывается, текст остаётся;
/// незакрытый тег закрывается в конце, лишний закрывающий пропускается;
/// `<f>` без числового `id` выбрасывается; `<x>` без годного `r` оставляет
/// только свой текст; `i` вне 0..4 прижимается к краю.
/// Любой текст разбирается без ошибок.
List<MarkupNode> parseMarkup(String text) => _Parser(text).parse();

// Тег: имя, необязательные атрибуты, необязательная косая черта.
final _tag = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9]*)(\s[^<>]*?)?(/?)>');

// Атрибут в двойных или одинарных кавычках.
final _attribute = RegExp(
  r'''([A-Za-z][A-Za-z0-9]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);

const _entities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"'};

final _entity = RegExp('&(amp|lt|gt|quot);');

final _styleByTag = {
  for (final MapEntry(:key, :value) in markupStyleTags.entries) value: key,
};

/// Открытый тег со своими детьми.
class _Frame {
  _Frame(
    this.tag, {
    this.style,
    this.strong = const [],
    this.morph,
    this.target,
  });

  final String tag;

  /// Значение `r` у `<x>`.
  final String? target;
  final MarkupStyle? style;
  final List<String> strong;
  final String? morph;
  final List<MarkupNode> children = [];
}

/// Однопроходный разбор со стеком открытых тегов.
class _Parser {
  _Parser(this._source);

  final String _source;
  final List<_Frame> _stack = [_Frame('')];
  final StringBuffer _text = StringBuffer();

  List<MarkupNode> parse() {
    var i = 0;
    while (i < _source.length) {
      final char = _source[i];
      if (char == '<') {
        final match = _tag.matchAsPrefix(_source, i);
        if (match != null) {
          _flushText();
          _handleTag(
            closing: match[1]!.isNotEmpty,
            name: match[2]!.toLowerCase(),
            attributes: _attributes(match[3] ?? ''),
            selfClosing: match[4]!.isNotEmpty,
          );
          i = match.end;
          continue;
        }
      } else if (char == '&') {
        final match = _entity.matchAsPrefix(_source, i);
        if (match != null) {
          _text.write(_entities[match[1]]);
          i = match.end;
          continue;
        }
      }
      _text.write(char);
      i++;
    }
    _flushText();
    while (_stack.length > 1) {
      _closeTop();
    }
    return _stack.single.children;
  }

  Map<String, String> _attributes(String source) => {
    for (final match in _attribute.allMatches(source))
      match[1]!.toLowerCase(): _unescape(match[2] ?? match[3] ?? ''),
  };

  String _unescape(String value) =>
      value.replaceAllMapped(_entity, (match) => _entities[match[1]]!);

  void _handleTag({
    required bool closing,
    required String name,
    required Map<String, String> attributes,
    required bool selfClosing,
  }) {
    if (closing) {
      _close(name);
      return;
    }
    switch (name) {
      case 'p':
        _add(const ParagraphBreak());
      case 'l':
        final indent = int.tryParse(attributes['i'] ?? '') ?? 0;
        _add(LineBreak(indent: indent.clamp(0, 4)));
      case 'f':
        final id = int.tryParse(attributes['id'] ?? '');
        if (id != null) {
          _add(FootnoteRef(id, attributes['c'] ?? ''));
        }
      case 'w':
        _open(
          _Frame(
            name,
            strong: (attributes['s'] ?? '')
                .split(RegExp(r'\s+'))
                .where((number) => number.isNotEmpty)
                .toList(),
            morph: (attributes['m'] ?? '').isEmpty ? null : attributes['m'],
          ),
          selfClosing,
        );
      case 'x':
        _open(_Frame(name, target: attributes['r']), selfClosing);
      case final tag when _styleByTag.containsKey(tag):
        _open(_Frame(tag, style: _styleByTag[tag]), selfClosing);
      // Неизвестный тег: сам тег пропадает, текст остаётся.
    }
  }

  void _open(_Frame frame, bool selfClosing) {
    _stack.add(frame);
    if (selfClosing) {
      _closeTop();
    }
  }

  /// Закрывает ближайший открытый тег [name] и всё, что открыто внутри него.
  void _close(String name) {
    final index = _stack.lastIndexWhere((frame) => frame.tag == name);
    if (index < 1) {
      return;
    }
    while (_stack.length > index) {
      _closeTop();
    }
  }

  void _closeTop() {
    final frame = _stack.removeLast();
    // Пустой участок ничего не показывает.
    if (frame.children.isEmpty) {
      return;
    }
    final style = frame.style;
    if (frame.tag == 'x') {
      // Без годного `r` тег пропадает, дети встают на его место.
      final range = RefRange.parse(frame.target ?? '');
      if (range == null) {
        frame.children.forEach(_add);
      } else {
        _add(CrossrefLink(range, frame.children));
      }
    } else if (style != null) {
      _add(StyledSpan(style, frame.children));
    } else {
      _add(
        TaggedWord(frame.children, strong: frame.strong, morph: frame.morph),
      );
    }
  }

  void _flushText() {
    if (_text.isEmpty) {
      return;
    }
    _add(TextRun(_text.toString()));
    _text.clear();
  }

  /// Добавляет узел в открытый тег; соседние куски текста сливаются.
  void _add(MarkupNode node) {
    final children = _stack.last.children;
    if (node is TextRun && children.isNotEmpty && children.last is TextRun) {
      children[children.length - 1] = TextRun(
        (children.last as TextRun).text + node.text,
      );
    } else {
      children.add(node);
    }
  }
}
