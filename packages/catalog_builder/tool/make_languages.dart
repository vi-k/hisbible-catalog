// Собирает таблицу языков `lib/src/ebible/languages.g.dart` из таблиц SIL
// ISO 639-3.
//
// Запуск из `packages/catalog_builder`: `dart run tool/make_languages.dart`.
// Код ISO 639-3 переходит в код ISO 639-1, если он есть, иначе в код 639-1
// его макроязыка (`cmn` → `zh`); прочие коды в таблицу не попадают
// и остаются как есть.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const _base = 'https://iso639-3.sil.org/sites/iso639-3/files/downloads';
const _codesUrl = '$_base/iso-639-3.tab';
const _macroUrl = '$_base/iso-639-3-macrolanguages.tab';

Future<void> main() async {
  final client = http.Client();
  try {
    final codes = await _fetch(client, _codesUrl);
    final macro = await _fetch(client, _macroUrl);
    final tags = _tags(codes.body, macro.body);
    final out = p.join(
      p.dirname(p.dirname(Platform.script.toFilePath())),
      'lib',
      'src',
      'ebible',
      'languages.g.dart',
    );
    File(out).writeAsStringSync(
      _source(tags, codes.date ?? 'unknown', macro.date ?? 'unknown'),
    );
    stdout.writeln('${tags.length} codes → $out');
  } finally {
    client.close();
  }
}

// Скачанная таблица и её дата из `Last-Modified`.
typedef _Table = ({String body, String? date});

Future<_Table> _fetch(http.Client client, String url) async {
  final response = await client.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  final modified = response.headers['last-modified'];

  return (
    body: response.body,
    date: modified == null ? null : _isoDate(HttpDate.parse(modified)),
  );
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// Код ISO 639-3 → код ISO 639-1 своего языка или макроязыка.
Map<String, String> _tags(String codesTab, String macroTab) {
  final part1 = <String, String>{};
  for (final row in _rows(codesTab, ['Id', 'Part1'])) {
    if (row[1].isNotEmpty) {
      part1[row[0]] = row[1];
    }
  }
  final tags = Map.of(part1);
  for (final row in _rows(macroTab, ['M_Id', 'I_Id'])) {
    final tag = part1[row[0]];
    if (tag != null) {
      tags.putIfAbsent(row[1], () => tag);
    }
  }

  return tags;
}

// Значения столбцов [columns] каждой строки таблицы с табуляцией.
Iterable<List<String>> _rows(String tab, List<String> columns) sync* {
  final lines = tab.replaceAll('\r\n', '\n').split('\n');
  final header = lines.first.replaceFirst('\uFEFF', '').split('\t');
  final indexes = [for (final column in columns) header.indexOf(column)];
  if (indexes.contains(-1)) {
    throw FormatException('No columns $columns in $header');
  }
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      continue;
    }
    final cells = line.split('\t');
    yield [
      for (final index in indexes)
        if (index < cells.length) cells[index].trim() else '',
    ];
  }
}

String _source(Map<String, String> tags, String codesDate, String macroDate) {
  final out = StringBuffer()
    ..writeln('// Сгенерировано tool/make_languages.dart, руками не править.')
    ..writeln('//')
    ..writeln('// Таблицы SIL ISO 639-3 и их даты (Last-Modified):')
    ..writeln('// $_codesUrl')
    ..writeln('// $_macroUrl')
    ..writeln('// iso-639-3.tab — $codesDate,')
    ..writeln('// iso-639-3-macrolanguages.tab — $macroDate.')
    ..writeln()
    ..writeln('/// Код ISO 639-3 → код ISO 639-1 языка или его макроязыка.')
    ..writeln('///')
    ..writeln('/// Кода, которого здесь нет, у языка в ISO 639-1 нет.')
    ..writeln('const Map<String, String> shortLanguageTags = {');
  for (final code in tags.keys.toList()..sort()) {
    out.writeln("  '$code': '${tags[code]}',");
  }
  out.writeln('};');

  return out.toString();
}
