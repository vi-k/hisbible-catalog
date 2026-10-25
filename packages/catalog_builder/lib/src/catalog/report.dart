/// Отчёт прогона сборки каталога, `out/report.md`.
final class BuildReport {
  /// Создаёт отчёт прогона [date].
  const BuildReport({
    required this.date,
    this.built = const [],
    this.unchanged = const [],
    this.withdrawn = const [],
    this.failed = const {},
    this.warnings = const {},
    this.waiting = const [],
    this.problems = const [],
  });

  /// Дата прогона, `YYYY-MM-DD`.
  final String date;

  /// Id собранных и выложенных модулей.
  final List<String> built;

  /// Id переводов без изменений.
  final List<String> unchanged;

  /// Id отозванных модулей.
  final List<String> withdrawn;

  /// Не собранные или не прошедшие проверку: id → причины.
  final Map<String, List<String>> failed;

  /// Предупреждения сборки по собранным модулям: id → предупреждения.
  final Map<String, List<String>> warnings;

  /// Id новых и обновлённых переводов, отложенных пределом `limit`.
  final List<String> waiting;

  /// Что не удалось при выкладке, но прогон не остановило: например,
  /// не удалился файл прежней версии.
  final List<String> problems;

  /// Отчёт в Markdown.
  ///
  /// Переводы без изменений и отложенные даны только числом: их бывает
  /// больше тысячи.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('# Catalog build $date')
      ..writeln()
      ..writeln('- Built: ${built.length}')
      ..writeln('- Unchanged: ${unchanged.length}')
      ..writeln('- Withdrawn: ${withdrawn.length}')
      ..writeln('- Failed: ${failed.length}')
      ..writeln('- Waiting for the next run: ${waiting.length}')
      ..writeln('- Publishing problems: ${problems.length}');
    void list(String title, Iterable<String> items) {
      if (items.isEmpty) {
        return;
      }
      out
        ..writeln()
        ..writeln('## $title')
        ..writeln();
      for (final item in items) {
        out.writeln('- $item');
      }
    }

    void sections(String title, Map<String, List<String>> items) {
      if (items.isEmpty) {
        return;
      }
      out
        ..writeln()
        ..writeln('## $title');
      for (final id in items.keys.toList()..sort()) {
        out
          ..writeln()
          ..writeln('### `$id`')
          ..writeln();
        for (final item in items[id]!) {
          out.writeln('- ${_escaped(item)}');
        }
      }
    }

    list('Built', [for (final id in built) '`$id`']);
    sections('Failed', failed);
    list('Withdrawn', [for (final id in withdrawn) '`$id`']);
    sections('Warnings', warnings);
    list('Publishing problems', problems.map(_escaped));

    return out.toString();
  }
}

// В причинах и предупреждениях бывают `\v`, `|strong=` и подобное: знаки
// разметки Markdown экранируются, чтобы отчёт показал их как есть.
String _escaped(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_<>|\[\]]'),
  (match) => '\\${match[0]}',
);
