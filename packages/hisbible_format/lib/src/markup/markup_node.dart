// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/refs/ref_range.dart';

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

  /// Жирный шрифт (`<b>`).
  bold,

  /// Малые прописные (`<sc>`): строчные буквы — заглавными малого размера.
  smallCaps,

  /// Источник цитаты (`<rq>`, USFM `\rq`): откуда цитата; места в нём —
  /// ссылки `<x>`.
  quoteSource,
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

/// Ссылка на место в Писании (`<x r>`); внутри — видимый текст ссылки.
final class CrossrefLink extends MarkupNode {
  /// Создаёт ссылку на [target] с содержимым [children].
  ///
  /// Без места ([target] равен `null`) в файл записывается один текст.
  const CrossrefLink(this.target, this.children);

  /// Куда ведёт ссылка, в нумерации модуля; `null` — места нет.
  final RefRange? target;

  /// Видимый текст ссылки по порядку.
  final List<MarkupNode> children;

  @override
  bool operator ==(Object other) =>
      other is CrossrefLink &&
      other.target == target &&
      _sameNodes(other.children, children);

  @override
  int get hashCode => Object.hash(target, Object.hashAll(children));

  @override
  String toString() => 'CrossrefLink($target, $children)';
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
  const LineBreak({this.indent = 0, this.align = ParagraphAlign.start});

  /// Глубина отступа.
  final int indent;

  /// Выравнивание строки: USFM `\qc` — по середине, `\qr` — по концу.
  final ParagraphAlign align;

  @override
  bool operator ==(Object other) =>
      other is LineBreak && other.indent == indent && other.align == align;

  @override
  int get hashCode => Object.hash(LineBreak, indent, align);

  @override
  String toString() => align == ParagraphAlign.start
      ? 'LineBreak($indent)'
      : 'LineBreak($indent, ${align.name})';
}

/// Начало нового абзаца (`<p/>`, `<p m="1"/>`, `<p b="1"/>`).
final class ParagraphBreak extends MarkupNode {
  /// Создаёт разрыв абзаца.
  const ParagraphBreak({
    this.continues = false,
    this.gap = false,
    this.indent = 0,
    this.align = ParagraphAlign.start,
  });

  /// Абзац продолжает прошлый после цитаты или стихов — USFM `\m`: печатают
  /// его без красной строки.
  final bool continues;

  /// Перед абзацем пустая строка — USFM `\b`: граница раздела в прозе или
  /// строфы в стихах.
  final bool gap;

  /// Отступ всего абзаца, 0..4 ступени: USFM `\pi#`, `\mi`, абзацы письма
  /// `\pm`, `\pmo`, `\pmc`.
  final int indent;

  /// Выравнивание абзаца: USFM `\pc` — по середине; `\pr`, `\pmr`, `\cls` —
  /// по концу строки.
  final ParagraphAlign align;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBreak &&
      other.continues == continues &&
      other.gap == gap &&
      other.indent == indent &&
      other.align == align;

  @override
  int get hashCode =>
      Object.hash(ParagraphBreak, continues, gap, indent, align);

  @override
  String toString() {
    final flags = [
      if (continues) 'continues',
      if (gap) 'gap',
      if (indent > 0) 'indent $indent',
      if (align != ParagraphAlign.start) align.name,
    ];
    return 'ParagraphBreak(${flags.join(', ')})';
  }
}

/// Начало строки таблицы (`<tr/>`, USFM `\tr`).
final class TableRow extends MarkupNode {
  /// Создаёт начало строки таблицы.
  const TableRow();

  @override
  bool operator ==(Object other) => other is TableRow;

  @override
  int get hashCode => (TableRow).hashCode;

  @override
  String toString() => 'TableRow()';
}

/// Начало ячейки таблицы (`<td/>`, `<td h="1"/>`, `<td a="c"/>`).
final class TableCell extends MarkupNode {
  /// Создаёт начало ячейки.
  const TableCell({this.header = false, this.align = ParagraphAlign.start});

  /// Ячейка — заголовок столбца: USFM `\th#`, `\thr#`.
  final bool header;

  /// Выравнивание ячейки: USFM `\tcc#` — по середине, `\tcr#`, `\thr#` —
  /// по концу строки.
  final ParagraphAlign align;

  @override
  bool operator ==(Object other) =>
      other is TableCell && other.header == header && other.align == align;

  @override
  int get hashCode => Object.hash(TableCell, header, align);

  @override
  String toString() {
    final flags = [
      if (header) 'header',
      if (align != ParagraphAlign.start) align.name,
    ];
    return 'TableCell(${flags.join(', ')})';
  }
}

/// Выравнивание абзаца или строки стихов.
enum ParagraphAlign {
  /// По началу строки: обычный абзац.
  start,

  /// По середине.
  center,

  /// По концу строки: справа, а в письме справа налево — слева.
  end,
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
