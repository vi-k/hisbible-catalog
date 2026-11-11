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

  /// Где у модуля Молитва Манассии; её ждёт `Versification.fromCanonical`.
  final ManassehHome manasseh;

  /// Схема книги; книга, которой нет в карте, — [VerseScheme.eng].
  VerseScheme of(int book) => schemes[book] ?? VerseScheme.eng;
}
