import 'package:hisbible_format/hisbible_format.dart';

/// Код письменности ISO 15924 по тексту [sample] и столбцу `script`
/// eBible.org.
///
/// Решает текст: самая частая письменность первых 10 000 букв [sample] по
/// диапазонам Юникода письменностей таблицы и греческой (`Grek`),
/// армянской (`Armn`), грузинской (`Geor`), хангыля (`Hang`) и других
/// письменностей переводов eBible (`Khmr`, `Sinh`, `Laoo`, `Mong`, `Cher`,
/// `Cans`, `Yiii`, `Vaii`, `Thaa`, `Java`, `Bali`, `Kali`, `Sylo`). Буква —
/// знак категории Юникода `L`: цифры, знаки препинания и огласовки внутри
/// этих диапазонов, как и буквы других письменностей, не считаются. Кана
/// считается вместе с иероглифами.
///
/// Иероглифы уточняет тот же текст: каны не меньше 5 % от иероглифов
/// с каной — `Jpan`; иначе считаются частые знаки пар «упрощённый —
/// полный» (说/說, 们/們, 这/這…), и больше упрощённых — `Hans`, больше
/// полных — `Hant`. Ни одного такого знака — `Hani`.
///
/// Столбец [csvScript] в eBible часто ошибается (у русского Синодального —
/// `Latin`), поэтому он нужен, только когда таких букв в [sample] нет,
/// и чтобы уточнить текст: `Han (Simplified variant)` при `Hani` по тексту
/// даёт `Hans`, `Coptic` при `Grek` — `Copt` (коптский текст часто набран
/// греческими буквами).
/// Столбец переводится по таблице (`Latin…` → `Latn`, `Devanagari…` →
/// `Deva`, `Ethiopic…` и `Amheric` → `Ethi`…). Не помогло ни то, ни другое
/// — `Zyyy`.
String scriptCodeOf(String csvScript, String sample) {
  final column = _columnScript(csvScript.trim());
  final letters = scriptOfText(sample);
  if ((letters, column) case ('Hani', 'Hans') || ('Grek', 'Copt')) {
    return column!;
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
  'Tifinagh': 'Tfng',
  'Khmer': 'Khmr',
  'Lao': 'Laoo',
  'Thaana': 'Thaa',
  'Unified Canadian Aboriginal Syllabics': 'Cans',
  'Kayah Li': 'Kali',
  'Syloti Nagri': 'Sylo',
};

// Начала имён столбца `script`: `Latin (Roman) with …`, `Devanagari
// (Nagari)`, `Ethiopic (Geʻez)`.
const _prefixes = [
  ('Latin', 'Latn'),
  ('Devanagari', 'Deva'),
  ('Ethiopic', 'Ethi'),
];
