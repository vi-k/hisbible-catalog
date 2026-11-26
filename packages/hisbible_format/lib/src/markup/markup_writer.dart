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
  MarkupStyle.bold: 'b',
  MarkupStyle.smallCaps: 'sc',
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
      case LineBreak(:final indent, :final align):
        out
          ..write('<l')
          ..write(_indent(indent))
          ..write(_align(align))
          ..write('/>');
      case TableRow():
        out.write('<tr/>');
      case TableCell(:final header, :final align):
        out
          ..write('<td')
          ..write(header ? ' h="1"' : '')
          ..write(_align(align))
          ..write('/>');
      case ParagraphBreak(
        :final continues,
        :final gap,
        :final indent,
        :final align,
      ):
        out
          ..write('<p')
          ..write(continues ? ' m="1"' : '')
          ..write(gap ? ' b="1"' : '')
          ..write(_indent(indent))
          ..write(_align(align))
          ..write('/>');
    }
  }
}

// Атрибут отступа: пусто у нуля.
String _indent(int indent) {
  final clamped = indent.clamp(0, 4);
  return clamped == 0 ? '' : ' i="$clamped"';
}

// Атрибут выравнивания: пусто у начала строки.
String _align(ParagraphAlign align) => switch (align) {
  ParagraphAlign.start => '',
  ParagraphAlign.center => ' a="c"',
  ParagraphAlign.end => ' a="e"',
};

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttribute(String text) => _escape(text).replaceAll('"', '&quot;');
