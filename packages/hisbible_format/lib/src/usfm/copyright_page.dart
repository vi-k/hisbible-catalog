/// Что приложение берёт из `copr.htm` eBible: имя перевода, язык страницы
/// и лицензию.
typedef CopyrightPage = ({String? name, String? language, String license});

/// Читает страницу `copr.htm` архива eBible.org [html].
///
/// `name` — текст `<h1>`, иначе `<title>`, без тегов и пробелов по краям;
/// `language` — `lang` тега `<html>`; `license` — [licenseOf] страницы
/// с текстом страницы без тегов в роли `copyright`.
CopyrightPage readCopyrightPage(String html) {
  final heading = _h1.firstMatch(html) ?? _title.firstMatch(html);
  final name = heading == null ? null : _nameText(heading[1]!);

  return (
    name: name == null || name.isEmpty ? null : name,
    language: _htmlLang.firstMatch(html)?[1],
    license: licenseOf(html, copyright: _plain(html, ' ')),
  );
}

// Имя из содержимого `<h1>` или `<title>`: без тегов, сущности HTML
// раскрыты, подряд идущие пробелы и переводы строк — один пробел.
String _nameText(String html) =>
    _decodeEntities(html.replaceAll(_tag, ''))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

// Раскрывает `&amp; &lt; &gt; &quot; &#39; &apos; &nbsp;` и числовые сущности
// (десятичные и шестнадцатеричные); незнакомые имена и негодные коды
// остаются как есть.
String _decodeEntities(String text) => text.replaceAllMapped(_entity, (match) {
  final body = match[1]!;
  if (body.startsWith('#')) {
    final hex = body.startsWith('#x') || body.startsWith('#X');
    final code = int.tryParse(
      body.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    final valid =
        code != null &&
        code > 0 &&
        code <= 0x10FFFF &&
        !(code >= 0xD800 && code <= 0xDFFF);

    return valid ? String.fromCharCode(code) : match[0]!;
  }

  return _namedEntities[body] ?? match[0]!;
});

final _entity = RegExp('&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

// Текст [html] без тегов (на их месте [gap]) и без пробелов по краям.
String _plain(String html, String gap) => html.replaceAll(_tag, gap).trim();

final _tag = RegExp('<[^>]*>');

final _h1 = RegExp(
  r'<h1\b[^>]*>(.*?)</h1>',
  caseSensitive: false,
  dotAll: true,
);

final _title = RegExp(
  r'<title\b[^>]*>(.*?)</title>',
  caseSensitive: false,
  dotAll: true,
);

final _htmlLang = RegExp(
  r"""<html\b[^>]*?\blang\s*=\s*["']([^"']+)["']""",
  caseSensitive: false,
);

/// Лицензия модуля по странице `copr.htm` архива eBible.org и столбцу
/// `Copyright` таблицы переводов [copyright].
///
/// Адрес `creativecommons.org/licenses/<вид>/<версия>` даёт
/// `CC-<ВИД>-<версия>` (`by-sa/4.0` → `CC-BY-SA-4.0`). CC0
/// (`creativecommons.org/publicdomain/zero/…`) и знак общественного
/// достояния (`…/publicdomain/mark/…`) — `PD`. Слова «public domain» без
/// адреса лицензии CC дают `PD`, только если и [copyright] говорит «public
/// domain»: ошибка в эту сторону выдала бы чужой текст за общественное
/// достояние. Отрицание («not in the public domain», «not a public domain»,
/// «no longer in the public domain», «isn't public domain») общественным
/// достоянием не считается ни там, ни там. Ничего из этого или страницы
/// нет — `redistributable`: eBible раздаёт перевод, но лицензию не называет.
String licenseOf(String? coprHtml, {String copyright = ''}) {
  if (coprHtml == null) {
    return 'redistributable';
  }
  if (_ccLicense.firstMatch(coprHtml) case final match?) {
    return 'CC-${match[1]!.toUpperCase()}-${match[2]}';
  }
  if (_publicDomainMark.hasMatch(coprHtml) ||
      (_saysPublicDomain(coprHtml) && _saysPublicDomain(copyright))) {
    return 'PD';
  }

  return 'redistributable';
}

final _ccLicense = RegExp(
  r'creativecommons\.org/licenses/([a-z]+(?:-[a-z]+)*)/(\d+(?:\.\d+)?)',
  caseSensitive: false,
);

final _publicDomainMark = RegExp(
  r'creativecommons\.org/publicdomain/(?:zero|mark)/',
  caseSensitive: false,
);

// Есть ли в [text] слова «public domain» без отрицания перед ними.
bool _saysPublicDomain(String text) =>
    _publicDomain.allMatches(text).any((match) => match[1] == null);

// Слова «public domain»; группа 1 — отрицание перед ними.
final _publicDomain = RegExp(
  r"(\b(?:not|no\s+longer|isn['’]t)\s+(?:a\s+|in\s+)?(?:the\s+)?)?"
  r'public\s+domain',
  caseSensitive: false,
);
