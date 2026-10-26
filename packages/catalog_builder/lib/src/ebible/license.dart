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
