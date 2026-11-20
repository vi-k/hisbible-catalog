import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

final vs = Versification.standard;

VerseRef r(int b, int c, int v) => VerseRef(b, c, v);

// Через каноническую `eng`: у Послания Иеремии она — Варух 6.
VerseRef toOrg(VerseRef ref) =>
    vs.fromCanonical(vs.toCanonical(ref, VerseScheme.rso), VerseScheme.org);

VerseRef fromOrg(VerseRef ref) =>
    vs.fromCanonical(vs.toCanonical(ref, VerseScheme.org), VerseScheme.rso);

/// Место таблицы `tool/rso_deutero`: `глава:стих`, `глава:стих-стих`
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
  final tables = Directory('tool/rso_deutero')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsv'))
      .toList();

  test('tables are there', () {
    expect(tables, hasLength(9));
  });

  for (final table in tables) {
    final code = table.uri.pathSegments.last.split('.').first;
    test('$code: every verse goes where the table says, and back', () {
      final book = BookCatalog.numberOfCode(code)!;
      final firstNamed = <(int, int), (int, int)>{};
      for (final line in table.readAsLinesSync()) {
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final cells = line.split('\t');
        final rus = _verses(cells[0]).single;
        if (cells[1] == '-') {
          continue;
        }
        final greek = _verses(cells[1]);
        expect(
          toOrg(r(book, rus.$1, rus.$2)),
          r(book, greek.first.$1, greek.first.$2),
          reason: '$code ${cells[0]}',
        );
        for (final verse in greek) {
          firstNamed.putIfAbsent(verse, () => rus);
        }
      }
      firstNamed.forEach((greek, rus) {
        expect(
          fromOrg(r(book, greek.$1, greek.$2)),
          r(book, rus.$1, rus.$2),
          reason: '$code ${greek.$1}:${greek.$2}',
        );
      });
    });
  }

  test('Sirach 43:15 of the Synodal is 43:14 of the Greek', () {
    expect(toOrg(r(280, 43, 15)), r(280, 43, 14));
    expect(fromOrg(r(280, 43, 14)), r(280, 43, 15));
  });

  test('a Synodal insertion goes to the Greek verse before it', () {
    // Сир 1:14 Синодального — вставка по латинскому тексту.
    expect(toOrg(r(280, 1, 14)), r(280, 1, 13));
  });
}
