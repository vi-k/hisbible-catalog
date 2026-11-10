import 'dart:convert';

/// Отпечатки изданий, из которых собраны модули каталога: id издания →
/// `editionDigest` его папки на момент сборки модуля. Пишет прогон каталога.
const editionsLockPath = 'sources/editions.lock.json';

/// Читает `editions.lock.json`: `{"<id>": {"digest": "<sha256>"}}`. Другой
/// вид — [FormatException].
Map<String, String> parseEditionsLock(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('editions.lock.json is not JSON: ${e.message}');
  }
  if (root is! Map<String, Object?>) {
    throw const FormatException('editions.lock.json: not an object');
  }

  return {
    for (final MapEntry(:key, :value) in root.entries)
      key: switch (value) {
        {'digest': final String digest} => digest,
        _ => throw FormatException(
          'editions.lock.json: $key has no string digest',
        ),
      },
  };
}

/// JSON `editions.lock.json` по id, с отступом в два пробела и переводом
/// строки в конце.
String editionsLockToJson(Map<String, String> digests) {
  final ids = digests.keys.toList()..sort();

  return '${const JsonEncoder.withIndent('  ').convert({
    for (final id in ids) id: {'digest': digests[id]},
  })}\n';
}
