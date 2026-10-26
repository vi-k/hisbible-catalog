import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/catalog/catalog_index.dart';
import 'package:catalog_builder/src/catalog/catalog_run.dart';
import 'package:catalog_builder/src/catalog/deletions.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/catalog/fonts.dart';
import 'package:catalog_builder/src/catalog/overrides.dart';
import 'package:catalog_builder/src/catalog/publisher.dart';
import 'package:catalog_builder/src/catalog/sources_lock.dart';
import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:path/path.dart' as p;

/// Команда `dart run catalog_builder:build` с аргументами [args]; вывод —
/// в [out] и [err], по умолчанию `stdout` и `stderr`.
///
/// Режимы и ключи описаны в `bin/build.dart`. Возвращает код выхода:
/// 0 — готово, 1 — не собрано или не всё удалено, 64 — неверные
/// аргументы.
Future<int> runBuildCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) => _Cli(out ?? stdout, err ?? stderr).run(args);

/// Адрес таблицы переводов [csv], если это адрес http(s); иначе `null`,
/// и [csv] — путь к файлу.
Uri? csvAddress(String csv) {
  final uri = Uri.tryParse(csv);

  return uri != null && (uri.isScheme('http') || uri.isScheme('https'))
      ? uri
      : null;
}

const _usage =
    'usage:\n'
    '  dart run catalog_builder:build [--csv <path or url>] [--limit <N>] '
    '[--deadline <minutes>] [--rebuild <id>]... [--allow-mass-withdrawal] '
    '[--dry-run] [--work <dir>]\n'
    '  dart run catalog_builder:build --one <zip> --csv <csv> '
    '[--out <file>]\n'
    '  dart run catalog_builder:build --apply-deletions <deletions.json>';

const _defaultCsv = 'https://ebible.org/Scriptures/translations.csv';

final _datedId = RegExp(r'^(.+)-\d{4}-\d{2}-\d{2}$');

/// Список удалений, которые ждут следующего прогона: пишется рядом
/// с указателем и коммитится с ним.
const pendingDeletionsPath = 'sources/pending-deletions.json';

/// Разобранные аргументы сборки: ключи со значениями и флаги в
/// `options`, id из повторяемого ключа `--rebuild` в `rebuild`.
typedef CliOptions = ({Map<String, String> options, List<String> rebuild});

/// Разбирает аргументы [args] сборки: ключи со значениями, флаги
/// `--dry-run` и `--allow-mass-withdrawal` (значение — пустая строка)
/// и повторяемый `--rebuild <id>`; незнакомый ключ, ключ без значения,
/// повтор другого ключа или id `--rebuild` не по [translationIdPattern] —
/// `null`.
CliOptions? parseCliOptions(List<String> args) {
  const valued = {
    '--one',
    '--csv',
    '--out',
    '--limit',
    '--deadline',
    '--work',
    '--apply-deletions',
  };
  const flags = {'--dry-run', '--allow-mass-withdrawal'};
  final options = <String, String>{};
  final rebuild = <String>[];
  for (var i = 0; i < args.length; i++) {
    final key = args[i];
    if (options.containsKey(key)) {
      return null;
    }
    if (key == '--rebuild' && i + 1 < args.length) {
      final id = args[++i];
      if (!translationIdPattern.hasMatch(id)) {
        return null;
      }
      rebuild.add(id);
    } else if (flags.contains(key)) {
      options[key] = '';
    } else if (valued.contains(key) && i + 1 < args.length) {
      options[key] = args[++i];
    } else {
      return null;
    }
  }

  return (options: options, rebuild: rebuild);
}

// Команда сборки с выводом в [_out] и [_err].
final class _Cli {
  _Cli(this._out, this._err);

  final StringSink _out;
  final StringSink _err;

  Future<int> run(List<String> args) async {
    final parsed = parseCliOptions(args);
    if (parsed == null) {
      return _badArguments();
    }
    final (:options, :rebuild) = parsed;
    if (rebuild.isNotEmpty &&
        (options.containsKey('--one') ||
            options.containsKey('--apply-deletions'))) {
      return _badArguments();
    }
    if (options.containsKey('--one')) {
      const allowed = {'--one', '--csv', '--out'};
      if (!options.keys.every(allowed.contains) ||
          !options.containsKey('--csv')) {
        return _badArguments();
      }

      return _one(options['--one']!, options['--csv']!, options['--out']);
    }
    final deletions = options['--apply-deletions'];
    if (deletions != null) {
      return options.length == 1 ? _applyDeletions(deletions) : _badArguments();
    }
    if (options.containsKey('--out')) {
      return _badArguments();
    }
    final limitText = options['--limit'] ?? '';
    final limit = limitText.isEmpty ? null : int.tryParse(limitText);
    if (limitText.isNotEmpty && (limit == null || limit < 0)) {
      return _badArguments();
    }
    final deadlineText = options['--deadline'] ?? '';
    final minutes = deadlineText.isEmpty ? null : int.tryParse(deadlineText);
    if (deadlineText.isNotEmpty && (minutes == null || minutes <= 0)) {
      return _badArguments();
    }

    return _catalog(
      csv: options['--csv'] ?? _defaultCsv,
      limit: limit,
      deadline: minutes == null
          ? null
          : DateTime.now().toUtc().add(Duration(minutes: minutes)),
      rebuild: rebuild.toSet(),
      allowMassWithdrawal: options.containsKey('--allow-mass-withdrawal'),
      dryRun: options.containsKey('--dry-run'),
      work: options['--work'] ?? p.join('out', 'work'),
    );
  }

  int _badArguments() {
    _err.writeln(_usage);

    return 64;
  }

  Future<int> _catalog({
    required String csv,
    required int? limit,
    required DateTime? deadline,
    required Set<String> rebuild,
    required bool allowMassWithdrawal,
    required bool dryRun,
    required String work,
  }) async {
    final fetcher = HttpFetcher();
    try {
      final translations = parseTranslationsCsv(await _readCsv(csv, fetcher));
      final publisher = dryRun ? DryRunPublisher() : GhPublisher();
      final result = await runCatalogBuild(
        translations: translations,
        previous:
            _readJson('index/index.json', CatalogIndex.parse) ??
            CatalogIndex.empty(),
        lock:
            _readJson('sources/sources.lock.json', SourcesLock.parse) ??
            const SourcesLock({}),
        overrides:
            _readJson('overrides.json', Overrides.parse) ?? const Overrides(),
        fonts:
            _readJson('fonts/fonts.lock.json', FontsLock.parse) ??
            FontsLock.empty,
        pending: _readJson(pendingDeletionsPath, parseDeletions) ?? const [],
        fetcher: fetcher,
        publisher: publisher,
        work: Directory(work)..createSync(recursive: true),
        now: DateTime.now().toUtc(),
        limit: limit,
        rebuild: rebuild,
        allowMassWithdrawal: allowMassWithdrawal,
        deadline: deadline,
        keepFiles: dryRun,
      );
      final out = dryRun ? p.join('out', 'dry-run') : 'out';
      final written = {
        dryRun ? p.join(out, 'index.json') : p.join('index', 'index.json'):
            result.index.toJson(),
        dryRun
            ? p.join(out, 'sources.lock.json')
            : p.join('sources', 'sources.lock.json'): result.lock
            .toJson(),
        p.join(out, 'report.md'): result.report.toMarkdown(),
        dryRun ? p.join(out, 'pending-deletions.json') : pendingDeletionsPath:
            deletionsToJson(result.deletions),
      };
      for (final MapEntry(:key, :value) in written.entries) {
        File(key)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(value);
        _out.writeln('wrote $key');
      }
      final report = result.report;
      _out.writeln(
        'built ${report.built.length}, unchanged ${report.unchanged.length}, '
        'withdrawn ${report.withdrawn.length}, failed ${report.failed.length}, '
        'waiting ${report.waiting.length}, '
        'skipped ${report.skipped.length}, '
        'deleted ${report.deleted.length}, '
        'to delete next run ${result.deletions.length}',
      );
      for (final line in [?report.stopped, ?report.withdrawalRefused]) {
        _err.writeln(line);
      }
      if (publisher is DryRunPublisher) {
        for (final delete in publisher.deletes) {
          _out.writeln('would delete $delete');
        }
        for (final upload in publisher.uploads) {
          _out.writeln('would upload $upload');
        }
      }

      return 0;
    } on Object catch (e) {
      _err.writeln('catalog build failed: $e');

      return 1;
    } finally {
      fetcher.close();
    }
  }

  // Удаляет файлы выпусков из списка [path] через `gh release`.
  Future<int> _applyDeletions(String path) async {
    final List<ReleaseAsset> deletions;
    try {
      deletions = parseDeletions(File(path).readAsStringSync());
    } on Exception catch (e) {
      _err.writeln('cannot read $path: $e');

      return 1;
    }
    final problems = await applyDeletions(deletions, GhPublisher());
    for (final problem in problems) {
      _err.writeln(problem);
    }
    _out.writeln(
      'deleted ${deletions.length - problems.length} of ${deletions.length}',
    );

    return problems.isEmpty ? 0 : 1;
  }

  // Таблица переводов из файла или по адресу http(s).
  Future<String> _readCsv(String csv, Fetcher fetcher) async {
    final uri = csvAddress(csv);
    if (uri != null) {
      return utf8.decode(await fetcher.get(uri));
    }

    return File(csv).readAsString();
  }

  // Файл [path], прочитанный [parse]; нет файла — `null`.
  T? _readJson<T>(String path, T Function(String json) parse) {
    final file = File(path);

    return file.existsSync() ? parse(file.readAsStringSync()) : null;
  }

  int _one(String zip, String csv, String? outPath) {
    final Map<String, EbibleTranslation> translations;
    try {
      translations = {
        for (final t in parseTranslationsCsv(File(csv).readAsStringSync()))
          t.translationId: t,
      };
    } on FileSystemException catch (e) {
      _err.writeln('cannot read $csv: ${e.message}');

      return 1;
    } on FormatException catch (e) {
      _err.writeln('$csv is not a translations table: ${e.message}');

      return 1;
    }
    final stem = p.basename(zip).replaceFirst(RegExp(r'_usfm\.zip$'), '');
    final translation =
        translations[stem] ?? translations[_datedId.firstMatch(stem)?[1]];
    if (translation == null) {
      _err.writeln('no translation $stem in $csv');

      return 1;
    }
    final out =
        outPath ??
        p.join(
          p.dirname(zip),
          '${translation.translationId}-${translation.updateDate}.hb',
        );
    final outcome = buildModule(
      translation,
      File(zip),
      out,
      overrides: const Overrides(),
      now: DateTime.now(),
    );
    switch (outcome) {
      case Built(:final path, :final size, :final sha256, :final books):
        _out
          ..writeln('built $path')
          ..writeln('size $size')
          ..writeln('sha256 $sha256')
          ..writeln('books OT ${books.ot}, NT ${books.nt}, DC ${books.dc}')
          ..writeln('warnings ${outcome.warnings.length}');
        for (final warning in outcome.warnings) {
          _out.writeln('  $warning');
        }

        return 0;
      case BuildFailed(:final reasons):
        _out.writeln('failed ${translation.translationId}');
        for (final reason in reasons) {
          _out.writeln('  $reason');
        }

        return 1;
    }
  }
}
