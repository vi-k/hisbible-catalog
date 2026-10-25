/// Лицензия модуля по странице `copr.htm` архива eBible.org.
///
/// Адрес `creativecommons.org/licenses/<вид>/<версия>` даёт
/// `CC-<ВИД>-<версия>` (`by-sa/4.0` → `CC-BY-SA-4.0`). CC0
/// (`creativecommons.org/publicdomain/zero/…`), знак общественного
/// достояния (`…/publicdomain/mark/…`) и слова «public domain» без адреса
/// лицензии CC — `PD`. Ничего из этого или страницы нет — `redistributable`:
/// eBible раздаёт перевод, но лицензию не называет.
String licenseOf(String? coprHtml) {
  if (coprHtml == null) {
    return 'redistributable';
  }
  if (_ccLicense.firstMatch(coprHtml) case final match?) {
    return 'CC-${match[1]!.toUpperCase()}-${match[2]}';
  }
  if (_publicDomain.hasMatch(coprHtml)) {
    return 'PD';
  }

  return 'redistributable';
}

final _ccLicense = RegExp(
  r'creativecommons\.org/licenses/([a-z]+(?:-[a-z]+)*)/(\d+(?:\.\d+)?)',
  caseSensitive: false,
);

final _publicDomain = RegExp(
  r'creativecommons\.org/publicdomain/(?:zero|mark)/|public\s+domain',
  caseSensitive: false,
);
