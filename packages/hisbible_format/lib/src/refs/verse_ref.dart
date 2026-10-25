// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Место в Писании: книга, глава и стих.
final class VerseRef {
  /// Создаёт место.
  const VerseRef(this.book, this.chapter, this.verse);

  /// Номер книги справочника.
  final int book;

  /// Номер главы.
  final int chapter;

  /// Номер стиха; 0 — надписание псалма.
  final int verse;

  @override
  bool operator ==(Object other) =>
      other is VerseRef &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(book, chapter, verse);

  @override
  String toString() => '$book:$chapter:$verse';
}
