import 'dart:convert';

import 'package:catalog_builder/src/catalog/publisher.dart';

/// JSON списка файлов выпусков к удалению, `out/deletions.json`:
/// `{"deletions": [{"release": …, "asset": …}]}` с отступом в два пробела
/// и переводом строки в конце.
String deletionsToJson(List<ReleaseAsset> deletions) {
  final items = [
    for (final (:release, :asset) in deletions)
      {'release': release, 'asset': asset},
  ];

  final json = const JsonEncoder.withIndent('  ').convert({'deletions': items});

  return '$json\n';
}

/// Читает список файлов к удалению, записанный [deletionsToJson].
///
/// Не JSON или другая форма — [FormatException].
List<ReleaseAsset> parseDeletions(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('deletions.json is not JSON: ${e.message}');
  }
  final items = root is Map<String, Object?> ? root['deletions'] : null;
  if (items is! List<Object?>) {
    throw const FormatException('deletions.json: deletions is not a list');
  }

  return [
    for (final item in items)
      if (item case {
        'release': final String release,
        'asset': final String asset,
      })
        (release: release, asset: asset)
      else
        throw FormatException('deletions.json: bad entry $item'),
  ];
}

/// Удаляет файлы [deletions] через [publisher] и возвращает, что
/// не удалилось; пустой список — удалено всё.
///
/// Неудачное удаление не останавливает остальные.
Future<List<String>> applyDeletions(
  List<ReleaseAsset> deletions,
  Publisher publisher,
) async {
  final problems = <String>[];
  for (final (:release, :asset) in deletions) {
    try {
      await publisher.deleteAsset(release, asset);
    } on Exception catch (e) {
      problems.add('cannot delete $asset from $release: $e');
    }
  }

  return problems;
}
