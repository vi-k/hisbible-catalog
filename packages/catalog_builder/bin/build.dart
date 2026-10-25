// Сборка каталога HisBible.
//
// Пока одна команда — собрать один модуль:
//   dart run catalog_builder:build --one <zip> --csv <translations.csv>
//       [--out <file>]
// Перевод ищется в `translations.csv` по имени архива:
// `<translationId>_usfm.zip` или `<translationId>-<UpdateDate>_usfm.zip`.
// Без `--out` модуль `<translationId>-<UpdateDate>.hb` пишется рядом
// с архивом. Код выхода: 0 — собран, 1 — не собран, 64 — неверные
// аргументы.

import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  exitCode = _run(args);
}

const _usage =
    'usage: dart run catalog_builder:build --one <zip> --csv <csv> '
    '[--out <file>]';

final _datedId = RegExp(r'^(.+)-\d{4}-\d{2}-\d{2}$');

int _run(List<String> args) {
  final options = _options(args);
  final zip = options?['--one'];
  final csv = options?['--csv'];
  if (options == null || zip == null || csv == null) {
    stderr.writeln(_usage);

    return 64;
  }
  final Map<String, EbibleTranslation> translations;
  try {
    translations = {
      for (final t in parseTranslationsCsv(File(csv).readAsStringSync()))
        t.translationId: t,
    };
  } on FileSystemException catch (e) {
    stderr.writeln('cannot read $csv: ${e.message}');

    return 1;
  } on FormatException catch (e) {
    stderr.writeln('$csv is not a translations table: ${e.message}');

    return 1;
  }
  final stem = p.basename(zip).replaceFirst(RegExp(r'_usfm\.zip$'), '');
  final translation =
      translations[stem] ?? translations[_datedId.firstMatch(stem)?[1]];
  if (translation == null) {
    stderr.writeln('no translation $stem in $csv');

    return 1;
  }
  final out =
      options['--out'] ??
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
      stdout
        ..writeln('built $path')
        ..writeln('size $size')
        ..writeln('sha256 $sha256')
        ..writeln('books OT ${books.ot}, NT ${books.nt}, DC ${books.dc}')
        ..writeln('warnings ${outcome.warnings.length}');
      for (final warning in outcome.warnings) {
        stdout.writeln('  $warning');
      }

      return 0;
    case BuildFailed(:final reasons):
      stdout.writeln('failed ${translation.translationId}');
      for (final reason in reasons) {
        stdout.writeln('  $reason');
      }

      return 1;
  }
}

// Значения ключей `--one`, `--csv` и `--out`; другой ключ, ключ без
// значения или повтор — `null`.
Map<String, String>? _options(List<String> args) {
  const known = {'--one', '--csv', '--out'};
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    final key = args[i];
    if (!known.contains(key) ||
        i + 1 >= args.length ||
        options.containsKey(key)) {
      return null;
    }
    options[key] = args[i + 1];
  }

  return options;
}
