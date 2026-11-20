/// Схемы нумерации стихов SIL; имена — как у файлов `.vrs`.
enum VerseScheme {
  /// Английская (по RSV) — каноническая: в ней хранятся места.
  eng,

  /// Еврейский текст: надписание псалма — стих 1.
  org,

  /// Синодальный перевод, полное издание.
  rso,

  /// Синодальный перевод, каноническое издание.
  rsc,

  /// Септуагинта: псалмы по греческому счёту, неканонические книги —
  /// как в [org].
  lxx,

  /// Вульгата: свой счёт Товита, Юдифи и Сираха.
  vul,
}

/// Где у перевода Молитва Манассии.
enum ManassehHome {
  /// Отдельная книга 145 из 15 стихов.
  book,

  /// 2 Паралипоменон 36:24–35, после стиха 23, как у Патриархии.
  chronicles36,

  /// 2 Паралипоменон 37:1–12, как в таблице SIL `rso`.
  chronicles37,
}

/// Схема нумерации каждой книги одного модуля.
final class BookSchemes {
  /// Создаёт карту схем: книга → схема.
  const BookSchemes({
    this.schemes = const {},
    this.uncertain = const {},
    this.manasseh = ManassehHome.book,
  });

  /// Схема каждой распознанной книги; ключ — номер книги справочника.
  final Map<int, VerseScheme> schemes;

  /// Книги, где лучшая схема совпала меньше чем в 95% глав.
  final Set<int> uncertain;

  /// Где у модуля Молитва Манассии; её ждут `Versification.toCanonical`
  /// и `Versification.fromCanonical`.
  final ManassehHome manasseh;

  /// Схема книги; книга, которой нет в карте, — [VerseScheme.eng].
  VerseScheme of(int book) => schemes[book] ?? VerseScheme.eng;
}

/// Сомнение в схеме книги модуля: `Versification.doubts`.
final class SchemeDoubt {
  /// Сомнение в схеме [scheme] книги [book].
  const SchemeDoubt({
    required this.book,
    required this.scheme,
    required this.matched,
    required this.chapters,
    required this.rival,
    required this.rivalMatched,
    required this.weak,
    required this.close,
    this.better,
    this.betterMatched = 0,
  });

  /// Номер книги.
  final int book;

  /// Схема книги в модуле.
  final VerseScheme scheme;

  /// Сколько глав совпало со [scheme] по последнему стиху.
  final int matched;

  /// Сколько глав в книге модуля.
  final int chapters;

  /// Другая схема: та, что совпала не реже ([close]), или лучшая из схем
  /// с другими длинами глав; `null` — у всех длины те же.
  final VerseScheme? rival;

  /// Сколько глав совпало с [rival].
  final int rivalMatched;

  /// [scheme] совпала меньше чем на 95% глав.
  final bool weak;

  /// В главах, где длины [scheme] и [rival] разные, [rival] совпала
  /// не реже: схему выбрал порядок, а не текст.
  final bool close;

  /// Схема, которую сборка этому переводу не предлагает (`lxx`, `vul` без
  /// подсказки языка), а она совпала хотя бы на две главы больше [scheme];
  /// `null` — такой нет.
  final VerseScheme? better;

  /// Сколько глав совпало с [better].
  final int betterMatched;
}
