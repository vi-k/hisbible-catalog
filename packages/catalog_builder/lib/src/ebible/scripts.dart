/// Код письменности ISO 15924 по тексту [sample] и столбцу `script`
/// eBible.org.
///
/// Решает текст: самая частая письменность первых 10 000 букв [sample] по
/// диапазонам Юникода письменностей таблицы и греческой (`Grek`),
/// армянской (`Armn`), грузинской (`Geor`) и хангыля (`Hang`); буквы других
/// письменностей, цифры и знаки не считаются. Столбец [csvScript] в eBible
/// часто ошибается (у русского Синодального — `Latin`), поэтому он нужен,
/// только когда таких букв в [sample] нет, и чтобы отличить упрощённые
/// иероглифы: `Han (Simplified variant)` при `Hani` по тексту даёт `Hans`.
/// Столбец переводится по таблице (`Latin…` → `Latn`, `Devanagari…` →
/// `Deva`, `Ethiopic…` и `Amheric` → `Ethi`…). Не помогло ни то, ни другое
/// — `Zyyy`.
String scriptCodeOf(String csvScript, String sample) {
  final column = _columnScript(csvScript.trim());
  final letters = _scriptOfLetters(sample);
  if (letters == 'Hani' && column == 'Hans') {
    return 'Hans';
  }

  return letters ?? column ?? 'Zyyy';
}

// Письменность по имени столбца `script` или `null`, если имя незнакомо.
String? _columnScript(String name) {
  if (_exactNames[name] case final code?) {
    return code;
  }
  for (final (prefix, code) in _prefixes) {
    if (name.startsWith(prefix)) {
      return code;
    }
  }

  return null;
}

// Имена столбца `script`, которые переводятся как есть.
const _exactNames = {
  'Cyrillic': 'Cyrl',
  'Arabic': 'Arab',
  'Hebrew': 'Hebr',
  'Amheric': 'Ethi',
  'Malayalam': 'Mlym',
  'Telugu': 'Telu',
  'Bengali': 'Beng',
  'CJK': 'Hani',
  'Han (Simplified variant)': 'Hans',
  'Coptic': 'Copt',
  'Tamil': 'Taml',
  'Tibetan': 'Tibt',
  'Gujarati': 'Gujr',
  'Kannada': 'Knda',
  'Oriya': 'Orya',
  'Thai': 'Thai',
  'Syriac': 'Syrc',
  'Burmese': 'Mymr',
  'Gurmukhi': 'Guru',
  'Tifenagh': 'Tfng',
};

// Начала имён столбца `script`: `Latin (Roman) with …`, `Devanagari
// (Nagari)`, `Ethiopic (Geʻez)`.
const _prefixes = [
  ('Latin', 'Latn'),
  ('Devanagari', 'Deva'),
  ('Ethiopic', 'Ethi'),
];

// Сколько букв выборки считается.
const _sampleLetters = 10000;

// Самая частая письменность первых букв [sample]; при равенстве — раньше
// по [_ranges]. `null` — букв этих письменностей нет.
String? _scriptOfLetters(String sample) {
  final counts = <String, int>{};
  var letters = 0;
  for (final rune in sample.runes) {
    final script = _scriptOfRune(rune);
    if (script == null) {
      continue;
    }
    counts[script] = (counts[script] ?? 0) + 1;
    if (++letters == _sampleLetters) {
      break;
    }
  }
  String? best;
  var bestCount = 0;
  for (final (script, _, _) in _ranges) {
    final count = counts[script] ?? 0;
    if (count > bestCount) {
      best = script;
      bestCount = count;
    }
  }

  return best;
}

String? _scriptOfRune(int rune) {
  for (final (script, from, to) in _ranges) {
    if (rune >= from && rune <= to) {
      return script;
    }
  }

  return null;
}

// Диапазоны букв: письменность, первый и последний код. `Hans` по буквам
// не отличить от `Hani`, его здесь нет. Коптские буквы греческого блока
// стоят раньше греческого диапазона и считаются коптскими.
const _ranges = [
  ('Latn', 0x41, 0x5A),
  ('Latn', 0x61, 0x7A),
  ('Latn', 0xC0, 0xD6),
  ('Latn', 0xD8, 0xF6),
  ('Latn', 0xF8, 0x2AF),
  ('Latn', 0x1E00, 0x1EFF),
  ('Latn', 0x2C60, 0x2C7F),
  ('Latn', 0xA720, 0xA7FF),
  ('Latn', 0xAB30, 0xAB6F),
  ('Cyrl', 0x400, 0x52F),
  ('Cyrl', 0x1C80, 0x1C8F),
  ('Cyrl', 0x2DE0, 0x2DFF),
  ('Cyrl', 0xA640, 0xA69F),
  ('Arab', 0x600, 0x6FF),
  ('Arab', 0x750, 0x77F),
  ('Arab', 0x8A0, 0x8FF),
  ('Arab', 0xFB50, 0xFDFF),
  ('Arab', 0xFE70, 0xFEFF),
  ('Hebr', 0x590, 0x5FF),
  ('Hebr', 0xFB1D, 0xFB4F),
  ('Deva', 0x900, 0x97F),
  ('Deva', 0xA8E0, 0xA8FF),
  ('Ethi', 0x1200, 0x139F),
  ('Ethi', 0x2D80, 0x2DDF),
  ('Ethi', 0xAB00, 0xAB2F),
  ('Mlym', 0xD00, 0xD7F),
  ('Telu', 0xC00, 0xC7F),
  ('Beng', 0x980, 0x9FF),
  ('Hani', 0x3400, 0x4DBF),
  ('Hani', 0x4E00, 0x9FFF),
  ('Hani', 0xF900, 0xFAFF),
  ('Hani', 0x20000, 0x323AF),
  ('Copt', 0x3E2, 0x3EF),
  ('Copt', 0x2C80, 0x2CFF),
  ('Taml', 0xB80, 0xBFF),
  ('Tibt', 0xF00, 0xFFF),
  ('Gujr', 0xA80, 0xAFF),
  ('Knda', 0xC80, 0xCFF),
  ('Orya', 0xB00, 0xB7F),
  ('Thai', 0xE00, 0xE7F),
  ('Syrc', 0x700, 0x74F),
  ('Mymr', 0x1000, 0x109F),
  ('Mymr', 0xA9E0, 0xA9FF),
  ('Mymr', 0xAA60, 0xAA7F),
  ('Guru', 0xA00, 0xA7F),
  ('Tfng', 0x2D30, 0x2D7F),
  ('Grek', 0x370, 0x3FF),
  ('Grek', 0x1F00, 0x1FFF),
  ('Armn', 0x531, 0x58F),
  ('Armn', 0xFB13, 0xFB17),
  ('Geor', 0x10A0, 0x10FF),
  ('Geor', 0x1C90, 0x1CBF),
  ('Geor', 0x2D00, 0x2D2F),
  ('Hang', 0x1100, 0x11FF),
  ('Hang', 0x3130, 0x318F),
  ('Hang', 0xAC00, 0xD7AF),
];
