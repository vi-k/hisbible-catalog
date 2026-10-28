// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/module/schema.dart';
import 'package:hisbible_format/src/refs/verse_ref.dart';

/// Место в Писании: один стих или промежуток от [start] до [end].
///
/// Книги — номера справочника; в строке записаны кодами `BookCatalog.codeOf`:
/// `MAT.1.1`, `GEN.1.1-GEN.2.3`.
final class RefRange {
  /// Создаёт место: один стих [start] или промежуток до [end].
  const RefRange(this.start, [this.end]);

  /// Первый стих.
  final VerseRef start;

  /// Последний стих; `null` — место из одного стиха.
  final VerseRef? end;

  /// Читает место из строки или возвращает `null`, если строку не прочесть.
  ///
  /// Глава должна быть в 1..[maxChapterNumber], стих — в 1..[maxVerseNumber],
  /// конец промежутка — не раньше начала.
  static RefRange? parse(String value) {
    final parts = value.split('-');
    if (parts.length > 2) {
      return null;
    }
    final start = _parseVerse(parts[0]);
    if (start == null) {
      return null;
    }
    if (parts.length == 1) {
      return RefRange(start);
    }
    final end = _parseVerse(parts[1]);
    if (end == null || _isBefore(end, start)) {
      return null;
    }

    return RefRange(start, end);
  }

  /// Строка места, которую читает [parse].
  String encode() {
    final end = this.end;
    if (end == null) {
      return _encodeVerse(start);
    }

    return '${_encodeVerse(start)}-${_encodeVerse(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is RefRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'RefRange(${encode()})';
}

final _verse = RegExp(r'^([A-Za-z0-9]+)\.(\d+)\.(\d+)$');

VerseRef? _parseVerse(String text) {
  final match = _verse.firstMatch(text);
  if (match == null) {
    return null;
  }
  final book = BookCatalog.numberOfCode(match[1]!);
  final chapter = int.tryParse(match[2]!);
  final verse = int.tryParse(match[3]!);
  if (book == null ||
      chapter == null ||
      verse == null ||
      chapter < 1 ||
      chapter > maxChapterNumber ||
      verse < 1 ||
      verse > maxVerseNumber) {
    return null;
  }

  return VerseRef(book, chapter, verse);
}

String _encodeVerse(VerseRef ref) =>
    '${BookCatalog.codeOf(ref.book)}.${ref.chapter}.${ref.verse}';

// Конец раньше начала: в одной книге — по главе и стиху, между книгами —
// по порядку номеров справочника.
bool _isBefore(VerseRef a, VerseRef b) {
  if (a.book != b.book) {
    return a.book < b.book;
  }
  if (a.chapter != b.chapter) {
    return a.chapter < b.chapter;
  }

  return a.verse < b.verse;
}
