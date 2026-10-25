import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:hisbible_format/hisbible_format.dart';

/// Проверяет модуль Библии [path] перед выпуском; пустой список — годен.
///
/// Причины, по которым модуль не годен:
/// - файл не открывается через [BibleModule.open] или глава не читается;
/// - главы книги идут не подряд с 1 или в главе нет стиха: отрывок книги,
///   начатый не с первой главы или с пропуском глав, тоже не годен;
/// - в тексте стиха осталась разметка USFM: `\` перед латинской буквой или
///   `|strong=`;
/// - число стихов Ветхого, Нового Завета или неканонических книг
///   отличается от `OTverses`, `NTverses` или `DCverses` [translation]
///   больше чем на 2% ожидаемого: |стихов − ожидаемое| × 50 > ожидаемое.
///   Ожидается 0 — стихов этой части быть не должно. Слитые стихи
///   (`\v 16-17`) считаются одним, как в `translations.csv`.
List<String> validateModule(String path, EbibleTranslation translation) {
  final BibleModule bible;
  try {
    bible = BibleModule.open(path);
  } on ModuleOpenException catch (e) {
    return ['the module does not open: ${e.problem}'];
  }
  try {
    return _check(bible, translation);
  } on Exception catch (e) {
    return ['the module does not read: $e'];
  } finally {
    bible.close();
  }
}

// Сколько мест с разметкой USFM называет причина.
const _shownPlaces = 10;

final _leftover = RegExp(r'\\[A-Za-z]|\|strong=');

List<String> _check(BibleModule bible, EbibleTranslation translation) {
  final reasons = <String>[];
  var ot = 0;
  var nt = 0;
  var dc = 0;
  final leftovers = <String>[];
  var leftoverCount = 0;
  for (final book in bible.books) {
    final chapters = book.chapters;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i] != i + 1) {
        reasons.add('${book.code}: chapter ${i + 1} has no verses');
        break;
      }
    }
    final info = BookCatalog.byNumber(book.number);
    for (final chapter in chapters) {
      final verses = bible.chapter(book.number, chapter);
      if (verses.isEmpty) {
        reasons.add('${book.code} $chapter: no verses');
      }
      bible
        ..headings(book.number, chapter)
        ..footnotes(book.number, chapter);
      for (final verse in verses) {
        if (_leftover.hasMatch(verse.text)) {
          if (++leftoverCount <= _shownPlaces) {
            leftovers.add('${book.code} $chapter:${verse.verse}');
          }
        }
      }
      if (info == null || info.deuterocanonical) {
        dc += verses.length;
      } else if (info.testament == Testament.old) {
        ot += verses.length;
      } else {
        nt += verses.length;
      }
    }
  }
  if (leftoverCount > 0) {
    final more = leftoverCount > _shownPlaces ? ', …' : '';
    reasons.add(
      'USFM markup left in $leftoverCount verses: '
      '${leftovers.join(', ')}$more',
    );
  }
  for (final (part, actual, column, expected) in [
    ('Old Testament', ot, 'OTverses', translation.otVerses),
    ('New Testament', nt, 'NTverses', translation.ntVerses),
    ('deuterocanonical books', dc, 'DCverses', translation.dcVerses),
  ]) {
    if ((actual - expected).abs() * 50 > expected) {
      reasons.add(
        '$part: $actual verses, $column $expected (more than 2% off)',
      );
    }
  }

  return reasons;
}
