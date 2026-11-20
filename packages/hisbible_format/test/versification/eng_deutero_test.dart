import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

final vs = Versification.standard;

VerseRef r(int b, int c, int v) => VerseRef(b, c, v);

VerseRef toOrg(VerseRef ref) => vs.fromCanonical(ref, VerseScheme.org);

VerseRef fromOrg(VerseRef ref) => vs.toCanonical(ref, VerseScheme.org);

/// Место таблицы `tool/eng_deutero`: `глава:стих`, `глава:стих-стих`
/// или `глава:стих-глава:стих` в одной главе.
List<(int, int)> _verses(String spec) {
  final match = RegExp(r'^(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?$').firstMatch(spec);
  if (match == null) {
    throw FormatException('Место таблицы', spec);
  }
  final chapter = int.parse(match[1]!);
  final first = int.parse(match[2]!);
  final last = match[4] == null ? first : int.parse(match[4]!);
  if (match[3] != null && int.parse(match[3]!) != chapter) {
    throw FormatException('Место через главу', spec);
  }

  return [for (var v = first; v <= last; v++) (chapter, v)];
}

void main() {
  final tables = Directory('tool/eng_deutero')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsv'))
      .toList();
  final baruch = BookCatalog.numberOfCode('BAR')!;

  test('tables are there', () {
    expect(tables, hasLength(7));
  });

  for (final table in tables) {
    final code = table.uri.pathSegments.last.split('.').first;
    test('$code: every verse goes where the table says, and back', () {
      final book = BookCatalog.numberOfCode(code)!;
      // Послание Иеремии в `eng` — и своя книга, и Варух 6 (как у KJV);
      // греческий стих ведёт в Варух 6.
      final letter = code == 'LJE';
      final firstNamed = <(int, int), (int, int)>{};
      for (final line in table.readAsLinesSync()) {
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final cells = line.split('\t');
        final eng = _verses(cells[0]).single;
        if (cells[1] == '-') {
          continue;
        }
        final greek = _verses(cells[1]);
        final want = r(book, greek.first.$1, greek.first.$2);
        expect(
          toOrg(r(book, eng.$1, eng.$2)),
          want,
          reason: '$code ${cells[0]}',
        );
        if (letter) {
          expect(toOrg(r(baruch, 6, eng.$2)), want, reason: 'BAR 6:${eng.$2}');
        }
        for (final verse in greek) {
          firstNamed.putIfAbsent(verse, () => eng);
        }
      }
      firstNamed.forEach((greek, eng) {
        expect(
          fromOrg(r(book, greek.$1, greek.$2)),
          letter ? r(baruch, 6, eng.$2) : r(book, eng.$1, eng.$2),
          reason: '$code ${greek.$1}:${greek.$2}',
        );
      });
    });
  }

  test('Sirach 33:17 of the Greek is 33:16 in English', () {
    expect(fromOrg(r(280, 33, 17)), r(280, 33, 16));
    expect(toOrg(r(280, 33, 17)), r(280, 33, 18));
  });

  test('an English verse missing in the Greek goes to the verse before it', () {
    // Сир 23:28 есть у KJV и Брентона, у Ральфса его нет.
    expect(toOrg(r(280, 23, 28)), r(280, 23, 27));
  });
}
