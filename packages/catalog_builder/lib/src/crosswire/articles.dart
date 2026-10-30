import 'package:catalog_builder/src/crosswire/osis_html.dart';
import 'package:catalog_builder/src/crosswire/zcom.dart';

/// Чем в записи стиха 1 отмечено начало толкования самого стиха — то, что
/// перед ним, введение к книге или главе.
enum ArticleMarker {
  /// Метка `<hi type="bold">Verse 1</hi>`, как у Clarke: толкование каждого
  /// стиха начинается своей меткой, так что запись без метки — вся введение.
  verseLabel,

  /// Абзац, который начинается ссылкой на стих 1 этой главы, как у KD:
  /// `<reference osisRef="Gen.1.1">` или текстом `Num 1:1`. Нет такого
  /// абзаца — введение целиком, если следующая запись начинается со стиха 2,
  /// а её первая ссылка — со стиха 1 (так osis2mod сдвигает толкование,
  /// когда стих 1 занят введением); иначе запись — толкование стиха.
  verseReference,
}

/// Что за часть толкований.
enum CommentPartKind {
  /// Толкование места.
  comment,

  /// Статья к книге: `chapter` 0.
  bookArticle,

  /// Статья к главе: `verse` 0.
  chapterArticle,
}

/// Часть толкований: место и текст OSIS.
final class CommentPart {
  /// Создаёт часть.
  const CommentPart({
    required this.kind,
    required this.book,
    required this.chapter,
    required this.verse,
    this.chapterEnd,
    this.verseEnd,
    required this.osis,
  });

  /// Толкование или статья.
  final CommentPartKind kind;

  /// Номер книги справочника.
  final int book;

  /// Глава начала; 0 — статья к книге.
  final int chapter;

  /// Стих начала; 0 — статья к главе или книге.
  final int verse;

  /// Глава конца; `null` — та же глава.
  final int? chapterEnd;

  /// Последний стих; `null` — одно место.
  final int? verseEnd;

  /// Текст: разметка OSIS.
  final String osis;
}

/// Части толкований и сколько записей стиха 1 поделено.
typedef SplitArticles = ({
  List<CommentPart> parts,
  int split,
  int whole,
  int shifted,
});

/// Делит записи [records] на толкования и статьи к книге и главе.
///
/// Запись книги — статья к книге, запись главы — статья к главе. Запись
/// стиха 1, которая начинается заголовком (`title`), делится по началу
/// толкования стиха ([marker]): что перед ним — статья к книге в главе 1
/// и статья к главе в других главах. Сколько записей поделено (`split`),
/// сколько целиком стали статьями (`whole`) и у скольких следующих записей
/// начало сдвинуто на стих 1 (`shifted`), — в итоге.
SplitArticles splitArticles(List<ZComRecord> records, ArticleMarker marker) {
  final parts = <CommentPart>[];
  var split = 0;
  var whole = 0;
  var shifted = 0;
  // Запись, чьё начало сдвигается на стих 1: её индекс.
  int? widen;
  for (final (i, record) in records.indexed) {
    CommentPart comment({String? osis, int? verse}) => CommentPart(
      kind: CommentPartKind.comment,
      book: record.book,
      chapter: record.chapter,
      verse: verse ?? record.verse,
      chapterEnd: record.chapterEnd,
      verseEnd: record.verseEnd,
      osis: osis ?? record.text,
    );
    CommentPart article(String osis) => record.chapter == 1
        ? CommentPart(
            kind: CommentPartKind.bookArticle,
            book: record.book,
            chapter: 0,
            verse: 0,
            osis: osis,
          )
        : CommentPart(
            kind: CommentPartKind.chapterArticle,
            book: record.book,
            chapter: record.chapter,
            verse: 0,
            osis: osis,
          );

    if (record.chapter == 0) {
      parts.add(
        CommentPart(
          kind: CommentPartKind.bookArticle,
          book: record.book,
          chapter: 0,
          verse: 0,
          osis: record.text,
        ),
      );
    } else if (record.verse == 0) {
      parts.add(
        CommentPart(
          kind: CommentPartKind.chapterArticle,
          book: record.book,
          chapter: record.chapter,
          verse: 0,
          osis: record.text,
        ),
      );
    } else if (widen == i) {
      parts.add(comment(verse: 1));
      shifted++;
    } else if (record.verse == 1 && _startsWithTitle(record.text)) {
      final at = switch (marker) {
        ArticleMarker.verseLabel => _verseLabel(record.text),
        ArticleMarker.verseReference => _verseReference(record),
      };
      final next = i + 1 < records.length ? records[i + 1] : null;
      if (at != null) {
        // Перед началом толкования одни вехи — делить нечего.
        if (osisToHtml(record.text.substring(0, at)).html.isEmpty) {
          parts.add(comment());
        } else {
          parts
            ..add(article(record.text.substring(0, at)))
            ..add(comment(osis: record.text.substring(at)));
          split++;
        }
      } else if (marker == ArticleMarker.verseLabel ||
          (next != null &&
              next.book == record.book &&
              next.chapter == record.chapter &&
              next.verse == 2 &&
              record.verseEnd == null &&
              _startsWithVerseOne(next.text, 0, next))) {
        parts.add(article(record.text));
        whole++;
        if (marker == ArticleMarker.verseReference) {
          widen = i + 1;
        }
      } else {
        parts.add(comment());
      }
    } else {
      parts.add(comment());
    }
  }

  return (parts: parts, split: split, whole: whole, shifted: shifted);
}

// Пробелы и вехи: `div`, `chapter`, `milestone` без содержимого.
final _skip = RegExp(r'(?:\s|<(?:div|chapter|milestone)\b[^>]*/>)*');
final _title = RegExp('<title[ >]');
final _label = RegExp(r'<hi type="bold">\s*Verse\s+1\s*</hi>');
// Начало абзаца: после вехи абзаца или после заголовка.
final _paragraphStart = RegExp(r'<div\b[^>]*\btype="x-p"[^>]*/>|</title>');
final _referenceTag = RegExp(r'<reference osisRef="([^".]+)\.(\d+)\.(\d+)[-"]');
final _referenceText = RegExp(
  r'(?:[1-3] ?)?[A-Z][a-z]{1,5}\.? ?(\d+):(\d+)(?!\d)',
);

bool _startsWithTitle(String osis) {
  final at = _skip.matchAsPrefix(osis)!.end;

  return _title.matchAsPrefix(osis, at) != null;
}

int? _verseLabel(String osis) => _label.firstMatch(osis)?.start;

// Начало первого абзаца, который открывается ссылкой на стих 1 главы
// записи; `null` — такого нет.
int? _verseReference(ZComRecord record) {
  for (final match in _paragraphStart.allMatches(record.text)) {
    if (_startsWithVerseOne(record.text, match.end, record)) {
      return match.end;
    }
  }

  return null;
}

// С места [at] текста [osis] после пробелов и вех стоит ссылка на стих 1
// главы записи [record]: тегом `reference` той же книги или текстом.
bool _startsWithVerseOne(String osis, int at, ZComRecord record) {
  final start = _skip.matchAsPrefix(osis, at)!.end;
  final tag = _referenceTag.matchAsPrefix(osis, start);
  if (tag != null) {
    return crosswireBook(tag[1]!) == record.book &&
        int.parse(tag[2]!) == record.chapter &&
        int.parse(tag[3]!) == 1;
  }
  final text = _referenceText.matchAsPrefix(osis, start);

  return text != null &&
      int.parse(text[1]!) == record.chapter &&
      int.parse(text[2]!) == 1;
}
