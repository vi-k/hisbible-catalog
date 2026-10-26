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
    this.skipped = const {},
    this.deletions = const [],
    this.deleted = const [],
    this.deletionProblems = const [],
    this.stopped,
    this.withdrawalRefused,
    this.rebuildMissed = const [],
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

  /// Пропущенные строки таблицы переводов: `translationId` → что не так.
  final Map<String, String> skipped;

  /// Файлы выпусков к удалению следующим прогоном: `<выпуск>/<файл>`.
  final List<String> deletions;

  /// Файлы прошлого прогона, удалённые в начале этого: `<выпуск>/<файл>`.
  final List<String> deleted;

  /// Почему не удалились файлы прошлого прогона; они ждут следующего.
  final List<String> deletionProblems;

  /// Почему прогон остановился раньше, или `null`, если дошёл до конца.
  final String? stopped;

  /// Почему прогон никого не отозвал, или `null`.
  final String? withdrawalRefused;

  /// Id из `--rebuild`, которые прогон не собрал: не взял, сборка
  /// не прошла или ждёт следующего прогона.
  final List<String> rebuildMissed;

  /// Что сказать о [rebuildMissed], или `null`, если пересобраны все.
  String? get rebuildProblem => rebuildMissed.isEmpty
      ? null
      : 'Rebuild not done: ${rebuildMissed.join(', ')}. Ids given to '
            '--rebuild are not remembered: request them again (in the '
            'workflow, the rebuild input)';

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
      ..writeln('- Skipped rows: ${skipped.length}')
      ..writeln('- Release files deleted: ${deleted.length}')
      ..writeln('- Release files to delete: ${deletions.length}');
    if (stopped case final stopped?) {
      out
        ..writeln()
        ..writeln('**$stopped; the rest waits for the next run.**');
    }
    for (final problem in [?withdrawalRefused, ?rebuildProblem]) {
      out
        ..writeln()
        ..writeln('**$problem.**');
    }
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
    list('Skipped rows', [
      for (final id in skipped.keys.toList()..sort())
        _skippedLine(id, skipped[id]!),
    ]);
    list('Withdrawn', [for (final id in withdrawn) '`$id`']);
    sections('Warnings', warnings);
    list('Release files deleted', [for (final file in deleted) '`$file`']);
    list('Release files not deleted', [
      for (final problem in deletionProblems) _escaped(problem),
    ]);
    list('Release files to delete next run', [
      for (final file in deletions) '`$file`',
    ]);

    return out.toString();
  }
}

// Строка пропущенной строки таблицы [id] с причиной [reason].
String _skippedLine(String id, String reason) {
  final name = id.isEmpty ? '(no translationId)' : _escaped(id);

  return '$name: ${_escaped(reason)}';
}

// В причинах и предупреждениях бывают `\v`, `|strong=` и подобное: знаки
// разметки Markdown экранируются, чтобы отчёт показал их как есть.
String _escaped(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_<>|\[\]]'),
  (match) => '\\${match[0]}',
);
