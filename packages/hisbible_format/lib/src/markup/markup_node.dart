// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Узел разобранной разметки стиха.
///
/// Узлы равны по содержимому: так их удобно сравнивать в тестах.
sealed class MarkupNode {
  /// Базовый конструктор узла.
  const MarkupNode();
}

/// Простой текст без разметки.
final class TextRun extends MarkupNode {
  /// Создаёт кусок текста.
  const TextRun(this.text);

  /// Текст с уже раскрытыми сущностями.
  final String text;

  @override
  bool operator ==(Object other) => other is TextRun && other.text == text;

  @override
  int get hashCode => Object.hash(TextRun, text);

  @override
  String toString() => 'TextRun($text)';
}

/// Стиль выделенного участка текста.
enum MarkupStyle {
  /// Слова Христа (`<wj>`).
  wordsOfChrist,

  /// Слова, добавленные переводчиком (`<add>`).
  added,

  /// Выделение (`<em>`).
  emphasis,

  /// Имя Бога (`<nd>`).
  divineName,

  /// Цитата (`<qt>`).
  quote,

  /// Примечание в тексте (`<n>`).
  note,

  /// Заголовок (`<h>`).
  heading,
}

/// Участок текста в одном стиле; внутри могут быть другие узлы.
final class StyledSpan extends MarkupNode {
  /// Создаёт участок стиля [style] с содержимым [children].
  const StyledSpan(this.style, this.children);

  /// Стиль участка.
  final MarkupStyle style;

  /// Содержимое участка по порядку.
  final List<MarkupNode> children;

  @override
  bool operator ==(Object other) =>
      other is StyledSpan &&
      other.style == style &&
      _sameNodes(other.children, children);

  @override
  int get hashCode => Object.hash(style, Object.hashAll(children));

  @override
  String toString() => 'StyledSpan($style, $children)';
}

/// Слово с номерами Стронга и морфологией.
///
/// Номера и морфология хранятся, но приложение их пока не показывает.
final class TaggedWord extends MarkupNode {
  /// Создаёт слово с содержимым [children], номерами [strong] и морфологией
  /// [morph].
  const TaggedWord(this.children, {this.strong = const [], this.morph});

  /// Содержимое слова по порядку.
  final List<MarkupNode> children;

  /// Номера Стронга: `H7225`, `G3779`.
  final List<String> strong;

  /// Код морфологии; `null` — не задан.
  final String? morph;

  @override
  bool operator ==(Object other) =>
      other is TaggedWord &&
      other.morph == morph &&
      _sameNodes(other.children, children) &&
      _sameStrings(other.strong, strong);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(children), Object.hashAll(strong), morph);

  @override
  String toString() => 'TaggedWord($children, $strong, $morph)';
}

/// Знак сноски; текст сноски лежит в модуле отдельно.
final class FootnoteRef extends MarkupNode {
  /// Создаёт знак сноски с номером [id] и знаком [caller].
  const FootnoteRef(this.id, this.caller);

  /// Номер сноски в модуле.
  final int id;

  /// Знак сноски в тексте, например `a`.
  final String caller;

  @override
  bool operator ==(Object other) =>
      other is FootnoteRef && other.id == id && other.caller == caller;

  @override
  int get hashCode => Object.hash(FootnoteRef, id, caller);

  @override
  String toString() => 'FootnoteRef($id, $caller)';
}

/// Новая строка стихов внутри стиха с отступом.
final class LineBreak extends MarkupNode {
  /// Создаёт перенос строки с отступом [indent] (0..4).
  const LineBreak({this.indent = 0});

  /// Глубина отступа.
  final int indent;

  @override
  bool operator ==(Object other) =>
      other is LineBreak && other.indent == indent;

  @override
  int get hashCode => Object.hash(LineBreak, indent);

  @override
  String toString() => 'LineBreak($indent)';
}

/// Начало нового абзаца (`<p/>`).
final class ParagraphBreak extends MarkupNode {
  /// Создаёт разрыв абзаца.
  const ParagraphBreak();

  @override
  bool operator ==(Object other) => other is ParagraphBreak;

  @override
  int get hashCode => (ParagraphBreak).hashCode;

  @override
  String toString() => 'ParagraphBreak()';
}

bool _sameNodes(List<MarkupNode> a, List<MarkupNode> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
