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

/// Схема нумерации каждой книги одного модуля.
final class BookSchemes {
  /// Создаёт карту схем: книга → схема.
  const BookSchemes({this.schemes = const {}, this.uncertain = const {}});

  /// Схема каждой распознанной книги; ключ — номер книги справочника.
  final Map<int, VerseScheme> schemes;

  /// Книги, где лучшая схема совпала меньше чем в 95% глав.
  final Set<int> uncertain;

  /// Схема книги; книга, которой нет в карте, — [VerseScheme.eng].
  VerseScheme of(int book) => schemes[book] ?? VerseScheme.eng;
}
