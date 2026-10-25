// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:convert';

/// Свои копии исходников, `sources/sources.lock.json`.
///
/// Вид файла: `{"sources": {"<translationId>": {"updateDate": …,
/// "sha256": …, "release": …, "asset": …, "fetched": …}}}`; незнакомые поля
/// при чтении пропускаются.
final class SourcesLock {
  /// Создаёт список исходников.
  const SourcesLock(this.entries);

  /// Читает список исходников из JSON [json].
  ///
  /// Не JSON или другая форма — [FormatException].
  factory SourcesLock.parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('sources.lock.json is not JSON: ${e.message}');
    }
    if (root is! Map<String, Object?>) {
      throw const FormatException('sources.lock.json is not an object');
    }
    final sources = root['sources'] ?? const <String, Object?>{};
    if (sources is! Map<String, Object?>) {
      throw const FormatException(
        'sources.lock.json: sources is not an object',
      );
    }

    return SourcesLock({
      for (final MapEntry(:key, :value) in sources.entries)
        key: LockedSource._parse(key, value),
    });
  }

  /// Исходники по id перевода.
  final Map<String, LockedSource> entries;

  /// JSON списка с отступом в два пробела, id по алфавиту, перевод строки
  /// в конце.
  String toJson() {
    final ids = entries.keys.toList()..sort();

    return '${const JsonEncoder.withIndent('  ').convert({
      'sources': {for (final id in ids) id: entries[id]!._toJson()},
    })}\n';
  }

  @override
  bool operator ==(Object other) =>
      other is SourcesLock &&
      other.entries.length == entries.length &&
      entries.entries.every((e) => other.entries[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(entries.values);
}

/// Своя копия исходника перевода: файл выпуска `sources-<дата>`.
final class LockedSource {
  /// Создаёт запись исходника.
  const LockedSource({
    required this.id,
    required this.updateDate,
    required this.sha256,
    required this.release,
    required this.asset,
    required this.fetched,
  });

  factory LockedSource._parse(String id, Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('sources.lock.json: $id is not an object');
    }
    String field(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('sources.lock.json: $id.$key is not a string');
      }

      return value;
    }

    return LockedSource(
      id: id,
      updateDate: field('updateDate'),
      sha256: field('sha256'),
      release: field('release'),
      asset: field('asset'),
      fetched: field('fetched'),
    );
  }

  /// Id перевода.
  final String id;

  /// `UpdateDate` перевода, с которого снята копия.
  final String updateDate;

  /// SHA-256 архива, 64 шестнадцатеричные цифры.
  final String sha256;

  /// Выпуск с копией: `sources-<дата>[-N]`.
  final String release;

  /// Имя файла копии: `<translationId>-<UpdateDate>_usfm.zip`.
  final String asset;

  /// Когда архив скачан с eBible, `YYYY-MM-DD`.
  final String fetched;

  Map<String, Object?> _toJson() => {
    'updateDate': updateDate,
    'sha256': sha256,
    'release': release,
    'asset': asset,
    'fetched': fetched,
  };

  @override
  bool operator ==(Object other) =>
      other is LockedSource &&
      other.id == id &&
      other.updateDate == updateDate &&
      other.sha256 == sha256 &&
      other.release == release &&
      other.asset == asset &&
      other.fetched == fetched;

  @override
  int get hashCode =>
      Object.hash(id, updateDate, sha256, release, asset, fetched);
}
