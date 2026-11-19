import 'package:hisbible_format/hisbible_format.dart';

/// Книга, разобранная из USFM.
final class UsfmBook {
  /// Создаёт разобранную книгу.
  const UsfmBook({
    required this.code,
    required this.intros,
    required this.verses,
    required this.headings,
    required this.notes,
    required this.droppedFragments,
    required this.unknownMarkers,
    this.header,
    this.toc1,
    this.toc2,
    this.toc3,
    this.chapterLabel,
  });

  /// Код книги из `\id`, например `GEN`; пусто, если `\id` нет.
  final String code;

  /// Заголовок книги из `\h`.
  final String? header;

  /// Полное название из `\toc1`.
  final String? toc1;

  /// Название из `\toc2`.
  final String? toc2;

  /// Сокращение из `\toc3`.
  final String? toc3;

  /// Слово «глава» из `\cl` до первой главы.
  final String? chapterLabel;

  /// Вступление до первой главы по порядку текста; сноски в нём — заметки
  /// [notes] с главой 0 и стихом 0.
  final List<UsfmIntro> intros;

  /// Куски стихов по порядку текста: свой на каждый `\v`, кроме того же
  /// номера подряд — он дописывается к своему куску.
  final List<UsfmVerse> verses;

  /// Заголовки по порядку текста.
  final List<UsfmHeading> headings;

  /// Сноски по порядку текста; номер первой — 1.
  final List<UsfmNote> notes;

  /// Сколько кусков текста вне стиха и заголовков без стиха выброшено.
  final int droppedFragments;

  /// Незнакомые маркеры без обратной косой черты, например `zz`.
  final Set<String> unknownMarkers;
}

/// Абзац вступления книги: заглавие (`\imt`, `\is`) или текст (`\ip`, `\im`…).
final class UsfmIntro {
  /// Создаёт абзац вступления вида [kind].
  const UsfmIntro({required this.kind, required this.nodes});

  /// Вид абзаца.
  final IntroKind kind;

  /// Разметка абзаца.
  final List<MarkupNode> nodes;
}

/// Кусок стиха книги USFM: то, что идёт за `\v` (и за таким же `\v`
/// сразу после него).
///
/// Кусок идёт от стиха [verse] с частью [part] до стиха [verseEnd] с частью
/// [partEnd]: `\v 6b-10a` — от `6b` до `10a`. Пустая часть — стих целиком.
final class UsfmVerse {
  /// Создаёт кусок, который начинается стихом [verse] главы [chapter].
  const UsfmVerse({
    required this.chapter,
    required this.verse,
    required this.nodes,
    this.verseEnd,
    this.part = '',
    this.partEnd = '',
    this.label,
    this.number,
  });

  /// Номер главы.
  final int chapter;

  /// Номер стиха, которым начинается кусок.
  final int verse;

  /// Буква части первого стиха (`a`, `б`) из `\v`; пустая — стих целиком.
  final String part;

  /// Буква части последнего стиха; пустая — стих целиком. Без [verseEnd]
  /// пустая.
  final String partEnd;

  /// Метка вместо номера из `\zvl`; пусто — ни номера, ни метки; `null` —
  /// стих с номером.
  final String? label;

  /// Номер, как его печатает издание, из `\vp` («1–6а»); `null` — свой.
  final String? number;

  /// Последний стих куска (`\v 16-17`), больше [verse]; `null` — кусок
  /// в одном стихе.
  final int? verseEnd;

  /// Разметка стиха.
  final List<MarkupNode> nodes;
}

/// Заголовок над куском стиха.
final class UsfmHeading {
  /// Создаёт заголовок над куском, который начинается стихом [verse] главы
  /// [chapter] с частью [part].
  const UsfmHeading({
    required this.chapter,
    required this.verse,
    required this.kind,
    required this.level,
    required this.nodes,
    this.part = '',
  });

  /// Номер главы.
  final int chapter;

  /// Номер стиха, которым начинается кусок под заголовком.
  final int verse;

  /// Часть стиха, которой начинается кусок под заголовком; пустая — стих
  /// целиком.
  final String part;

  /// Вид заголовка.
  final HeadingKind kind;

  /// Уровень: цифра маркера, без цифры — 1; у `\sp` — 3.
  final int level;

  /// Разметка заголовка.
  final List<MarkupNode> nodes;
}

/// Сноска книги.
final class UsfmNote {
  /// Создаёт сноску [id] к стиху [verse] главы [chapter].
  const UsfmNote({
    required this.id,
    required this.chapter,
    required this.verse,
    required this.kind,
    required this.caller,
    required this.nodes,
  });

  /// Номер сноски в книге, с 1; его несёт `FootnoteRef.id`.
  final int id;

  /// Номер главы.
  final int chapter;

  /// Номер стиха; у сноски в заголовке — стих под заголовком.
  final int verse;

  /// Вид сноски.
  final FootnoteKind kind;

  /// Знак сноски в тексте; пусто — знака нет.
  final String caller;

  /// Разметка текста сноски.
  final List<MarkupNode> nodes;
}
