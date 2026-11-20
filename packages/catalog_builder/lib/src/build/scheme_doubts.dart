import 'package:hisbible_format/hisbible_format.dart';

/// Сомнения в схемах книг записанного модуля [bible]
/// (`Versification.doubts`): подсказки — по его языку, книги [settled]
/// (схема задана в `overrides.json`) не проверяются.
List<SchemeDoubt> moduleSchemeDoubts(
  BibleModule bible, {
  Set<int> settled = const {},
}) {
  final hints = Versification.hintsOf(bible.meta.language);

  return Versification.standard.doubts(
    bible.lastVerses(),
    bible.schemes,
    russianFlag: hints.russianFlag,
    preferred: hints.preferred,
    settled: settled,
  );
}

/// Предупреждение сборки о сомнении [doubt] в книге с кодом [code]: схема,
/// сколько глав совпало, лучшая другая схема и почему книга сомнительна.
String schemeWarning(SchemeDoubt doubt, String code) {
  final why = [
    if (doubt.weak) 'matches fewer than 95% of chapters',
    if (doubt.close) 'another scheme is as close',
    if (doubt.synodal) 'Synodal scheme outside ru, uk and be',
  ];
  final rival = doubt.rival == null
      ? ''
      : ', ${doubt.rival!.name} ${doubt.rivalMatched}';

  return '$code: numbering scheme ${doubt.scheme.name} is doubtful '
      '(${doubt.matched} of ${doubt.chapters} chapters$rival): '
      '${why.join('; ')}';
}
