import 'package:hisbible_format/src/markup/markup_node.dart';

/// Текст для копирования: без сносок, переносы и разрывы абзацев — пробел.
///
/// Пробел ставится только между словами: в начале и в конце текста,
/// а также рядом с другим пробелом его нет. Слово с номерами Стронга
/// даёт свой текст.
String plainText(List<MarkupNode> nodes) {
  final out = StringBuffer();
  var pendingBreak = false;
  var last = '';

  void write(List<MarkupNode> list) {
    for (final node in list) {
      switch (node) {
        case TextRun(:final text):
          if (text.isEmpty) {
            break;
          }
          if (pendingBreak && last.isNotEmpty && !_isSpace(last)) {
            if (!_isSpace(text[0])) {
              out.write(' ');
            }
          }
          pendingBreak = false;
          out.write(text);
          last = text[text.length - 1];
        case StyledSpan(:final children) || TaggedWord(:final children):
          write(children);
        case LineBreak() || ParagraphBreak():
          pendingBreak = true;
        case FootnoteRef():
          break;
      }
    }
  }

  write(nodes);
  return out.toString();
}

bool _isSpace(String char) => char.trim().isEmpty;
