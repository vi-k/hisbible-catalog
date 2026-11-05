import 'package:hisbible_format/hisbible_format.dart';

/// Книга, разобранная из USFM.
final class UsfmBook {
  /// Создаёт разобранную книгу.
  const UsfmBook({
    required this.code,
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

  /// Стихи по порядку текста.
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

/// Стих книги USFM.
final class UsfmVerse {
  /// Создаёт стих [verse] главы [chapter].
  const UsfmVerse({
    required this.chapter,
    required this.verse,
    required this.nodes,
    this.verseEnd,
  });

  /// Номер главы.
  final int chapter;

  /// Номер стиха.
  final int verse;

  /// Последний стих объединённых стихов (`\v 16-17`); `null` — стих один.
  final int? verseEnd;

  /// Разметка стиха.
  final List<MarkupNode> nodes;
}

/// Заголовок над стихом.
final class UsfmHeading {
  /// Создаёт заголовок над стихом [verse] главы [chapter].
  const UsfmHeading({
    required this.chapter,
    required this.verse,
    required this.kind,
    required this.level,
    required this.nodes,
  });

  /// Номер главы.
  final int chapter;

  /// Номер стиха, над которым стоит заголовок.
  final int verse;

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
