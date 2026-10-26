// Версия модуля каталога: дата `UpdateDate` eBible и, возможно, наша
// правка после точки.
final _moduleVersion = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:\.[1-9][0-9]*)?$');

/// Дата `YYYY-MM-DD` версии модуля [version], или `null`, если [version] —
/// не версия.
///
/// Версия — `YYYY-MM-DD` (`UpdateDate` перевода на eBible.org), за которой
/// может идти `.N`, наша правка, N от 1 без ведущих нулей: `2025-03-04`,
/// `2025-03-04.1`. Дата должна существовать в календаре. Версии
/// сравниваются только на неравенство; показывается их дата.
String? moduleVersionDate(String version) {
  final match = _moduleVersion.firstMatch(version);
  if (match == null) {
    return null;
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }

  return version.substring(0, 10);
}
