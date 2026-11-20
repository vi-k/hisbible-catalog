/// Проход по скачанным модулям каталога: книги с сомнительной схемой
/// нумерации (`moduleSchemeDoubts`).
///
/// `dart run catalog_builder:scheme_doubts <папка .hb> <overrides.json>
/// <out.tsv>` — строка на книгу: модуль, язык, книга, схема, совпало глав,
/// глав, другая схема, совпало с ней, почему.
library;

import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'usage: scheme_doubts <dir of .hb> <overrides.json> <out.tsv>',
    );
    exitCode = 64;

    return;
  }
  final overrides = Overrides.parse(File(args[1]).readAsStringSync());
  final files =
      Directory(args[0])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final out = StringBuffer(
    'module\tlanguage\tbook\tscheme\tmatched\tchapters\trival\t'
    'rival_matched\twhy\n',
  );
  var books = 0;
  var doubtful = 0;
  for (final file in files) {
    final BibleModule bible;
    try {
      bible = BibleModule.open(file.path);
    } on ModuleOpenException catch (e) {
      stderr.writeln('${file.path}: ${e.problem}');
      continue;
    }
    try {
      final id = bible.meta.catalogId ?? file.uri.pathSegments.last;
      final codes = {for (final b in bible.books) b.number: b.code};
      books += codes.length;
      final settled = (overrides.schemes[id] ?? const {}).keys.toSet();
      for (final d in moduleSchemeDoubts(bible, settled: settled)) {
        doubtful++;
        final why = [
          if (d.weak) 'weak',
          if (d.close) 'close',
          if (d.synodal) 'synodal',
        ];
        out.writeln(
          [
            id,
            bible.meta.language,
            codes[d.book] ?? d.book,
            d.scheme.name,
            d.matched,
            d.chapters,
            d.rival?.name ?? '',
            d.rivalMatched,
            why.join(','),
          ].join('\t'),
        );
      }
    } finally {
      bible.close();
    }
  }
  File(args[2]).writeAsStringSync(out.toString());
  stdout.writeln('modules ${files.length}, books $books, doubtful $doubtful');
}
