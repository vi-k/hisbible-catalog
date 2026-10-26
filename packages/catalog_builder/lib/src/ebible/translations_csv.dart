import 'package:catalog_builder/src/ebible/languages.g.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:hisbible_format/hisbible_format.dart';

/// Перевод из `translations.csv` eBible.org.
///
/// Поля — столбцы таблицы с теми же именами; числа без значения — 0.
final class EbibleTranslation {
  /// Создаёт перевод.
  const EbibleTranslation({
    required this.languageCode,
    required this.translationId,
    required this.languageName,
    required this.languageNameInEnglish,
    required this.title,
    required this.description,
    required this.redistributable,
    required this.copyright,
    required this.updateDate,
    required this.publicationUrl,
    required this.otVerses,
    required this.ntVerses,
    required this.dcVerses,
    required this.textDirection,
    required this.downloadable,
    required this.shortTitle,
    required this.script,
  });

  /// Код языка ISO 639-3: `languageCode`.
  final String languageCode;

  /// Id перевода, например `eng-kjv2006`: `translationId`.
  final String translationId;

  /// Название языка на нём самом: `languageName`.
  final String languageName;

  /// Название языка по-английски: `languageNameInEnglish`.
  final String languageNameInEnglish;

  /// Название перевода на его языке: `title`.
  final String title;

  /// Описание перевода: `description`.
  final String description;

  /// Разрешена ли раздача: `Redistributable`.
  final bool redistributable;

  /// Копирайт: `Copyright`.
  final String copyright;

  /// Дата обновления, `YYYY-MM-DD`: `UpdateDate`.
  final String updateDate;

  /// Страница перевода: `publicationURL`.
  final String publicationUrl;

  /// Число стихов Ветхого Завета: `OTverses`.
  final int otVerses;

  /// Число стихов Нового Завета: `NTverses`.
  final int ntVerses;

  /// Число стихов неканонических книг: `DCverses`.
  final int dcVerses;

  /// Направление письма: `textDirection`; всё, кроме `rtl`, — слева
  /// направо.
  final WritingDirection textDirection;

  /// Можно ли скачать: `downloadable`.
  final bool downloadable;

  /// Короткое название: `shortTitle`.
  final String shortTitle;

  /// Письменность по-английски, например `Latin`: `script`.
  final String script;
}

/// Разбирает `translations.csv` eBible.org: строка заголовков, затем
/// переводы.
///
/// Столбцы ищутся по именам, лишние пропускаются, недостающие
/// необязательные пусты. Понимает BOM в начале, поля в кавычках с запятыми,
/// переводами строк и `""` внутри, концы строк `\n` и `\r\n`.
///
/// Таблица без какого-нибудь из [requiredTranslationColumns] или строка,
/// где `Redistributable` или `downloadable` не `true` и не `false` (регистр
/// любой), — [FormatException]: eBible поменял таблицу, и сборка по ней
/// отозвала бы переводы, которые никто не отзывал.
List<EbibleTranslation> parseTranslationsCsv(String csv) {
  final rows = _csvRows(csv);
  if (rows.isEmpty) {
    throw const FormatException('Empty translations table');
  }
  final header = rows.first;
  final missing = [
    for (final name in requiredTranslationColumns)
      if (!header.contains(name)) name,
  ];
  if (missing.isNotEmpty) {
    throw FormatException(
      'No ${missing.join(', ')} column${missing.length == 1 ? '' : 's'} '
      'in the translations table: $header',
    );
  }
  final columns = {for (var i = 0; i < header.length; i++) header[i]: i};

  return [
    for (final row in rows.skip(1))
      if (row.any((cell) => cell.isNotEmpty))
        _translation((name) {
          final index = columns[name];

          return index == null || index >= row.length ? '' : row[index].trim();
        }),
  ];
}

/// Столбцы `translations.csv`, без которых таблица не годится: по ним
/// сборка выбирает переводы, узнаёт обновления и проверяет модули.
const requiredTranslationColumns = [
  'translationId',
  'languageCode',
  'title',
  'Redistributable',
  'downloadable',
  'UpdateDate',
  'OTverses',
  'NTverses',
  'DCverses',
  'textDirection',
];

EbibleTranslation _translation(String Function(String) cell) {
  bool flag(String name) => switch (cell(name).toLowerCase()) {
    'true' => true,
    'false' => false,
    final value => throw FormatException(
      'translations table, ${cell('translationId')}: $name is "$value", '
      'expected True or False',
    ),
  };
  int number(String name) => int.tryParse(cell(name)) ?? 0;

  return EbibleTranslation(
    languageCode: cell('languageCode'),
    translationId: cell('translationId'),
    languageName: cell('languageName'),
    languageNameInEnglish: cell('languageNameInEnglish'),
    title: cell('title'),
    description: cell('description'),
    redistributable: flag('Redistributable'),
    copyright: cell('Copyright'),
    updateDate: cell('UpdateDate'),
    publicationUrl: cell('publicationURL'),
    otVerses: number('OTverses'),
    ntVerses: number('NTverses'),
    dcVerses: number('DCverses'),
    textDirection: cell('textDirection') == 'rtl'
        ? WritingDirection.rtl
        : WritingDirection.ltr,
    downloadable: flag('downloadable'),
    shortTitle: cell('shortTitle'),
    script: cell('script'),
  );
}

// Строки CSV по RFC 4180: поле в кавычках может держать запятые, переводы
// строк и `""`.
List<List<String>> _csvRows(String csv) {
  final text = withoutBom(csv);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = [];
  }

  while (i < text.length) {
    final char = text[i];
    if (quoted) {
      if (char != '"') {
        field.write(char);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\n') {
      endRow();
    } else if (char != '\r') {
      field.write(char);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }

  return rows;
}

/// Самый короткий тег BCP 47 для кода ISO 639-3 из `languageCode`.
///
/// Код ISO 639-1, если он есть; иначе код 639-1 макроязыка (`cmn` → `zh`);
/// иначе код как есть. Пустой код — `und`.
String bcp47Of(String languageCode) {
  final code = languageCode.trim();
  if (code.isEmpty) {
    return 'und';
  }

  return shortLanguageTags[code] ?? code;
}
