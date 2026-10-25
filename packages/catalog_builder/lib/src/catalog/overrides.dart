import 'dart:convert';

/// Ручные поправки каталога из `overrides.json`.
final class Overrides {
  /// Создаёт поправки; без аргументов — поправок нет.
  const Overrides({this.abbreviations = const {}, this.exclude = const {}});

  /// Читает `{"abbreviations": {"<id>": "<аббревиатура>"}, "exclude":
  /// ["<id>"]}`; оба ключа необязательны.
  ///
  /// Не JSON или другая форма — [FormatException].
  factory Overrides.parse(String json) {
    final root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('overrides.json is not an object');
    }
    final abbreviations = root['abbreviations'] ?? const <String, Object?>{};
    final exclude = root['exclude'] ?? const <Object?>[];
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

    return Overrides(
      abbreviations: Map.unmodifiable(abbreviations.cast<String, String>()),
      exclude: Set.unmodifiable(exclude.cast<String>()),
    );
  }

  /// Своя аббревиатура модуля: id перевода → аббревиатура.
  final Map<String, String> abbreviations;

  /// Id переводов, которых в каталоге не будет.
  final Set<String> exclude;
}
