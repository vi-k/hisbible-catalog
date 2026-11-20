import 'dart:convert';

import 'package:hisbible_format/hisbible_format.dart';

/// Ручные поправки каталога из `overrides.json`.
final class Overrides {
  /// Создаёт поправки; без аргументов — поправок нет.
  const Overrides({
    this.abbreviations = const {},
    this.exclude = const {},
    this.schemes = const {},
  });

  /// Читает `{"abbreviations": {"<id>": "<аббревиатура>"}, "exclude":
  /// ["<id>"], "schemes": {"<id>": {"<код книги>": "<схема>"}}}`; все ключи
  /// необязательны. Код книги — код SIL (`TOB`), схема — имя
  /// [VerseScheme] (`org`).
  ///
  /// Не JSON, другая форма, неизвестный код книги или схема —
  /// [FormatException].
  factory Overrides.parse(String json) {
    final root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('overrides.json is not an object');
    }
    final abbreviations = root['abbreviations'] ?? const <String, Object?>{};
    final exclude = root['exclude'] ?? const <Object?>[];
    final schemes = root['schemes'] ?? const <String, Object?>{};
    if (abbreviations is! Map<String, Object?> ||
        abbreviations.values.any((value) => value is! String)) {
      throw const FormatException(
        'overrides.json: abbreviations is not a map of strings',
      );
    }
    if (exclude is! List<Object?> || exclude.any((id) => id is! String)) {
      throw const FormatException(
        'overrides.json: exclude is not a list of strings',
      );
    }

    if (schemes is! Map<String, Object?>) {
      throw const FormatException('overrides.json: schemes is not a map');
    }

    return Overrides(
      abbreviations: Map.unmodifiable(abbreviations.cast<String, String>()),
      exclude: Set.unmodifiable(exclude.cast<String>()),
      schemes: Map.unmodifiable({
        for (final MapEntry(key: id, value: books) in schemes.entries)
          id: _bookSchemes(id, books),
      }),
    );
  }

  // Схемы книг одного перевода: `{"<код книги>": "<схема>"}`.
  static Map<int, VerseScheme> _bookSchemes(String id, Object? books) {
    if (books is! Map<String, Object?>) {
      throw FormatException('overrides.json: schemes of $id is not a map');
    }
    final names = {for (final s in VerseScheme.values) s.name: s};
    final result = <int, VerseScheme>{};
    for (final MapEntry(key: code, value: name) in books.entries) {
      final book = BookCatalog.bySilCode(code)?.number;
      final scheme = names[name];
      if (book == null || scheme == null) {
        throw FormatException(
          'overrides.json: schemes of $id: unknown book or scheme',
          '$code: $name',
        );
      }
      result[book] = scheme;
    }

    return Map.unmodifiable(result);
  }

  /// Своя аббревиатура модуля: id перевода → аббревиатура.
  final Map<String, String> abbreviations;

  /// Id переводов, которых в каталоге не будет.
  final Set<String> exclude;

  /// Схема нумерации книг, заданная руками: id перевода → номер книги →
  /// схема. Она побеждает схему, которую сборка распознала по длинам глав.
  final Map<String, Map<int, VerseScheme>> schemes;
}
