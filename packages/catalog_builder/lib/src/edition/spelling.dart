/// Таблица написания: старая форма слова и её современная замена.
final class SpellingTable {
  /// Таблица из пар «слово строчными буквами без ударения → замена».
  SpellingTable(this.words);

  /// Пары «старое → новое», обе части строчными буквами.
  final Map<String, String> words;
}

/// Разбирает таблицу `старое\tновое`; пустые строки и `#` пропускаются.
SpellingTable parseSpellingTable(String tsv) {
  final words = <String, String>{};
  final lines = tsv.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('\t');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw FormatException('Строка ${i + 1}: нужно «старое<TAB>новое»');
    }
    words[parts[0]] = parts[1];
  }

  return SpellingTable(words);
}

const _stress = '́';

// Маркер (`\add`, `\add*`, `\+w`), атрибут (`|…` до следующего маркера)
// или слово из кириллических букв и ударений. Маркеры и атрибуты идут
// первыми, чтобы слово внутри них не заменялось.
final _token = RegExp(r'(\\\+?[A-Za-z0-9]+\*?)|(\|[^\\]*)|([Ѐ-ӿ́]+)');

/// Заменяет в тексте USFM [usfm] целые слова по [table].
///
/// Регистр переносится на замену (`Святаго` → `Святого`, `СВЯТАГО` →
/// `СВЯТОГО`), ударение остаётся на той же по счёту букве.
({String text, int replaced}) applySpelling(String usfm, SpellingTable table) {
  var replaced = 0;
  final text = usfm.replaceAllMapped(_token, (match) {
    final word = match.group(3);
    if (word == null) return match.group(0)!;
    final fixed = _fixWord(word, table);
    if (fixed == null) return word;
    replaced++;

    return fixed;
  });

  return (text: text, replaced: replaced);
}

String? _fixWord(String word, SpellingTable table) {
  // Буквы без ударений и номера букв, после которых стоит ударение.
  final letters = StringBuffer();
  final stresses = <int>[];
  for (final rune in word.runes) {
    final char = String.fromCharCode(rune);
    if (char == _stress) {
      stresses.add(letters.length - 1);
    } else {
      letters.write(char);
    }
  }
  final plain = letters.toString();
  final replacement = table.words[plain.toLowerCase()];
  if (replacement == null) return null;

  final upper = plain.toUpperCase();
  final cased = plain.length > 1 && plain == upper
      ? replacement.toUpperCase()
      : plain[0] != plain[0].toLowerCase()
      ? replacement[0].toUpperCase() + replacement.substring(1)
      : replacement;

  final result = StringBuffer();
  for (var i = 0; i < cased.length; i++) {
    result.write(cased[i]);
    if (stresses.contains(i)) result.write(_stress);
  }

  return result.toString();
}
