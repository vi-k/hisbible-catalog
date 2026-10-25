/// Лицензия модуля по странице `copr.htm` архива eBible.org.
///
/// Адрес `creativecommons.org/licenses/<вид>/<версия>` даёт
/// `CC-<ВИД>-<версия>` (`by-sa/4.0` → `CC-BY-SA-4.0`). CC0
/// (`creativecommons.org/publicdomain/zero/…`), знак общественного
/// достояния (`…/publicdomain/mark/…`) и слова «public domain» без адреса
/// лицензии CC — `PD`; отрицание («not in the public domain», «not public
/// domain») общественным достоянием не считается. Ничего из этого или
/// страницы нет — `redistributable`: eBible раздаёт перевод, но лицензию
/// не называет.
String licenseOf(String? coprHtml) {
  if (coprHtml == null) {
    return 'redistributable';
  }
  if (_ccLicense.firstMatch(coprHtml) case final match?) {
    return 'CC-${match[1]!.toUpperCase()}-${match[2]}';
  }
  if (_publicDomainMark.hasMatch(coprHtml) ||
      _publicDomain.allMatches(coprHtml).any((match) => match[1] == null)) {
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

// Слова «public domain»; группа 1 — отрицание перед ними.
final _publicDomain = RegExp(
  r'(\bnot\s+(?:in\s+)?(?:the\s+)?)?public\s+domain',
  caseSensitive: false,
);
