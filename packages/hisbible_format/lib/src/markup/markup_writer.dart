import 'package:hisbible_format/src/markup/markup_node.dart';

/// Теги стилей в файле модуля.
const markupStyleTags = {
  MarkupStyle.wordsOfChrist: 'wj',
  MarkupStyle.added: 'add',
  MarkupStyle.emphasis: 'em',
  MarkupStyle.divineName: 'nd',
  MarkupStyle.quote: 'qt',
  MarkupStyle.note: 'n',
  MarkupStyle.heading: 'h',
};

/// Записывает дерево узлов строкой разметки модуля.
///
/// В тексте и значениях атрибутов `&`, `<`, `>` и `"` записываются
/// сущностями; `parseMarkup` читает запись обратно в то же дерево.
String writeMarkup(List<MarkupNode> nodes) {
  final out = StringBuffer();
  _write(nodes, out);
  return out.toString();
}

void _write(List<MarkupNode> nodes, StringBuffer out) {
  for (final node in nodes) {
    switch (node) {
      case TextRun(:final text):
        out.write(_escape(text));
      case StyledSpan(:final style, :final children):
        final tag = markupStyleTags[style]!;
        out.write('<$tag>');
        _write(children, out);
        out.write('</$tag>');
      case TaggedWord(:final children, :final strong, :final morph):
        out.write('<w');
        if (strong.isNotEmpty) {
          out.write(' s="${_escapeAttribute(strong.join(' '))}"');
        }
        if (morph != null && morph.isNotEmpty) {
          out.write(' m="${_escapeAttribute(morph)}"');
        }
        out.write('>');
        _write(children, out);
        out.write('</w>');
      case CrossrefLink(:final target, :final children):
        if (target == null) {
          _write(children, out);
        } else {
          out.write('<x r="${_escapeAttribute(target.encode())}">');
          _write(children, out);
          out.write('</x>');
        }
      case FootnoteRef(:final id, :final caller):
        out.write('<f id="$id" c="${_escapeAttribute(caller)}"/>');
      case LineBreak(:final indent):
        final clamped = indent.clamp(0, 4);
        out.write(clamped == 0 ? '<l/>' : '<l i="$clamped"/>');
      case ParagraphBreak():
        out.write('<p/>');
    }
  }
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttribute(String text) => _escape(text).replaceAll('"', '&quot;');
