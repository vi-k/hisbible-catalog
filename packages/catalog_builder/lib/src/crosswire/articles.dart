import 'package:catalog_builder/src/crosswire/osis_html.dart';
import 'package:catalog_builder/src/crosswire/zcom.dart';
import 'package:hisbible_format/hisbible_format.dart';

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
  int widened,
});

/// Делит записи [records] на толкования и статьи к книге и главе.
///
/// Запись книги — статья к книге, запись главы — статья к главе. Запись
/// стиха 1, которая начинается заголовком (`title`), делится по началу
/// толкования стиха ([marker]): что перед ним — статья к книге в главе 1
/// и статья к главе в других главах. Сколько записей поделено (`split`),
/// сколько целиком стали статьями (`whole`) и у скольких следующих записей
/// начало сдвинуто на стих 1 (`shifted`), — в итоге.
///
/// У [ArticleMarker.verseReference] место толкования ещё и сверяется с его
/// ведущей ссылкой — ссылкой, которая одна стоит в первом абзаце: если она
/// в той же книге и главе и её промежуток содержит место записи, место
/// толкования — промежуток ссылки (`widened`). Толкование, которое так
/// стало начинаться со стиха 1, делает запись стиха 1 этой главы без
/// ведущей ссылки, начатую заголовком, статьёй (она считается в `whole`).
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

  if (marker != ArticleMarker.verseReference) {
    return (
      parts: parts,
      split: split,
      whole: whole,
      shifted: shifted,
      widened: 0,
    );
  }
  final (:widened, :articles) = _widenToLeadingReference(parts);

  return (
    parts: parts,
    split: split,
    whole: whole + articles,
    shifted: shifted,
    widened: widened,
  );
}

// Расширяет места толкований [parts] до их ведущих ссылок и делает
// статьями записи стиха 1, чьё место заняло расширенное толкование.
({int widened, int articles}) _widenToLeadingReference(
  List<CommentPart> parts,
) {
  var widened = 0;
  // Главы, где толкование после расширения начинается со стиха 1.
  final fromVerseOne = <(int, int)>{};
  for (final (i, part) in parts.indexed) {
    if (part.kind != CommentPartKind.comment || part.chapterEnd != null) {
      continue;
    }
    final range = _leadingRange(part.osis);
    final end = range?.end ?? range?.start;
    if (range == null ||
        end == null ||
        range.start.book != part.book ||
        range.start.chapter != part.chapter ||
        end.chapter != part.chapter ||
        range.start.verse > part.verse ||
        end.verse < (part.verseEnd ?? part.verse)) {
      continue;
    }
    final verseEnd = end.verse == range.start.verse ? null : end.verse;
    if (range.start.verse == part.verse && verseEnd == part.verseEnd) {
      continue;
    }
    parts[i] = CommentPart(
      kind: CommentPartKind.comment,
      book: part.book,
      chapter: part.chapter,
      verse: range.start.verse,
      verseEnd: verseEnd,
      osis: part.osis,
    );
    widened++;
    if (range.start.verse == 1 && part.verse != 1) {
      fromVerseOne.add((part.book, part.chapter));
    }
  }
  var articles = 0;
  for (final (i, part) in parts.indexed) {
    if (part.kind == CommentPartKind.comment &&
        part.verse == 1 &&
        part.verseEnd == null &&
        fromVerseOne.contains((part.book, part.chapter)) &&
        _startsWithTitle(part.osis) &&
        _leadingRange(part.osis) == null) {
      parts[i] = CommentPart(
        kind: part.chapter == 1
            ? CommentPartKind.bookArticle
            : CommentPartKind.chapterArticle,
        book: part.book,
        chapter: part.chapter == 1 ? 0 : part.chapter,
        verse: 0,
        osis: part.osis,
      );
      articles++;
    }
  }

  return (widened: widened, articles: articles);
}

// Ведущая ссылка записи: после вех тег `reference`, а за ним сразу граница
// абзаца или конец записи; `null` — такой ссылки нет или её не прочесть.
RefRange? _leadingRange(String osis) {
  final start = _skip.matchAsPrefix(osis)!.end;
  final match = _leadingReference.matchAsPrefix(osis, start);
  if (match == null) {
    return null;
  }
  final after = _skip.matchAsPrefix(osis, match.end)!;
  final rest = osis.substring(match.end, after.end);
  if (after.end < osis.length && !rest.contains(_paragraphMilestone)) {
    return null;
  }

  return parseOsisRef(match[1]!);
}

// Пробелы и вехи: `div`, `chapter`, `milestone` без содержимого.
final _skip = RegExp(r'(?:\s|<(?:div|chapter|milestone)\b[^>]*/>)*');
final _title = RegExp('<title[ >]');
final _label = RegExp(r'<hi type="bold">\s*Verse\s+1\s*</hi>');
// Начало абзаца: после вехи абзаца или после заголовка.
final _paragraphStart = RegExp(r'<div\b[^>]*\btype="x-p"[^>]*/>|</title>');
final _referenceTag = RegExp(r'<reference osisRef="([^".]+)\.(\d+)\.(\d+)[-"]');
final _leadingReference = RegExp(
  '<reference osisRef="([^"]+)">[^<]*</reference>',
);
final _paragraphMilestone = RegExp(r'<div\b[^>]*\btype="x-p"[^>]*/>');
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
