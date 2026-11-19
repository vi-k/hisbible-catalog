// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Место в Писании: книга, глава, стих и часть стиха.
final class VerseRef {
  /// Создаёт место; [part] — буква части стиха, пустая — стих целиком.
  const VerseRef(this.book, this.chapter, this.verse, [this.part = '']);

  /// Номер книги справочника.
  final int book;

  /// Номер главы.
  final int chapter;

  /// Номер стиха; 0 — надписание псалма.
  final int verse;

  /// Буква части стиха, как её пишет источник (`a`, `б`); пустая — стих
  /// целиком.
  final String part;

  /// То же место без части: стих целиком.
  VerseRef get whole => part.isEmpty ? this : VerseRef(book, chapter, verse);

  @override
  bool operator ==(Object other) =>
      other is VerseRef &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.part == part;

  @override
  int get hashCode => Object.hash(book, chapter, verse, part);

  /// Вид для отладки: `230:4:6b`. Строки для хранения из него не строят.
  @override
  String toString() => '$book:$chapter:$verse$part';
}
