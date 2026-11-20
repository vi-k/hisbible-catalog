/// Проход по скачанным модулям каталога: книги с сомнительной схемой
/// нумерации (`moduleSchemeDoubts`).
///
/// `dart run catalog_builder:scheme_doubts <папка .hb> <overrides.json>
/// <out.tsv>` — строка на книгу: модуль, язык, книга, схема в модуле, схема,
/// которую дала бы пересборка, совпало с ней глав, глав, другая схема,
/// совпало с ней, почему, совпало глав с каждой схемой.
/// Сомнения считаются для схемы пересборки; книга,
/// у которой пересборка сменила бы схему, идёт в список и без сомнений
/// (`changed`).
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
    'module\tlanguage\tbook\tbuilt\tscheme\tmatched\tchapters\trival\t'
    'rival_matched\twhy\tscores\n',
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
      final hints = Versification.hintsOf(bible.meta.language);
      final chapters = bible.lastVerses();
      final fresh = Versification.standard.detect(
        chapters,
        russianFlag: hints.russianFlag,
        preferred: hints.preferred,
      );
      final doubts = {
        for (final d in Versification.standard.doubts(
          chapters,
          fresh,
          russianFlag: hints.russianFlag,
          preferred: hints.preferred,
          settled: settled,
        ))
          d.book: d,
      };
      for (final book in codes.keys) {
        final d = doubts[book];
        final built = bible.schemes.of(book);
        final changed = !settled.contains(book) && built != fresh.of(book);
        if (d == null && !changed) {
          continue;
        }
        doubtful++;
        final why = [
          if (d?.weak ?? false) 'weak',
          if (d?.close ?? false) 'close',
          if (d?.better case final better?) 'better:${better.name}',
          if (changed) 'changed',
        ];
        out.writeln(
          [
            id,
            bible.meta.language,
            codes[book],
            built.name,
            fresh.of(book).name,
            d?.matched ?? '',
            d?.chapters ?? chapters[book]?.length ?? 0,
            d?.rival?.name ?? '',
            d?.rivalMatched ?? '',
            why.join(','),
            [
              for (final s in VerseScheme.values)
                '${s.name}=${_score(chapters[book] ?? const {}, s, book)}',
            ].join(' '),
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

int _score(Map<int, int> lasts, VerseScheme scheme, int book) {
  final expected = Versification.standard.lastVerses(scheme, book);

  return lasts.entries.where((e) => expected[e.key] == e.value).length;
}
