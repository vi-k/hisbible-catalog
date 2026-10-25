// Класс неизменяем: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:hisbible_format/src/module/schema.dart';
import 'package:hisbible_format/src/module_type.dart';
import 'package:hisbible_format/src/problems.dart';

/// Ключи и значения таблицы `meta` модуля.
///
/// Ключи и их значения описаны в `FORMAT.md`, раздел «Формат файла».
/// Ключ `paragraphs` пишет и читает сам файл модуля, в описание он не входит.
/// Незнакомые ключи хранятся в [extra] как есть.
final class ModuleMeta {
  /// Создаёт описание модуля.
  const ModuleMeta({
    required this.type,
    required this.abbreviation,
    required this.name,
    required this.language,
    required this.direction,
    this.script,
    this.license = 'unknown',
    this.copyright,
    this.description,
    this.source,
    this.sourceUrl,
    this.version,
    this.created,
    this.catalog,
    this.catalogId,
    this.chapterWord,
    this.chapterWordPsalms,
    this.numbering,
    this.generator,
    this.extra = const {},
  });

  /// Читает описание из пар `meta`.
  ///
  /// Нет обязательного ключа или он пуст — [ModuleOpenException]
  /// с [MissingMeta]; незнакомый `type` — с [UnsupportedType]. `direction`
  /// кроме `rtl` читается как [WritingDirection.ltr].
  factory ModuleMeta.fromValues(Map<String, String> values) {
    String required(String key) {
      final value = values[key];
      if (value == null || value.trim().isEmpty) {
        throw ModuleOpenException(MissingMeta(key));
      }

      return value;
    }

    final typeText = required('type');
    final type = typeOfValue(typeText);
    if (type == null) {
      throw ModuleOpenException(UnsupportedType(typeText));
    }
    final abbreviation = required('abbreviation');
    final name = required('name');
    final language = required('language');
    final direction = required('direction') == 'rtl'
        ? WritingDirection.rtl
        : WritingDirection.ltr;
    final license = values['license'];

    return ModuleMeta(
      type: type,
      abbreviation: abbreviation,
      name: name,
      language: language,
      direction: direction,
      script: _filled(values['script']),
      license: license == null || license.isEmpty ? 'unknown' : license,
      copyright: _filled(values['copyright']),
      description: _filled(values['description']),
      source: _filled(values['source']),
      sourceUrl: _filled(values['source_url']),
      version: _filled(values['version']),
      created: _filled(values['created']),
      catalog: _filled(values['catalog']),
      catalogId: _filled(values['catalog_id']),
      chapterWord: _filled(values['chapter_word']),
      chapterWordPsalms: _filled(values['chapter_word_psalms']),
      numbering: _filled(values['numbering']),
      generator: _filled(values['generator']),
      extra: Map.unmodifiable({
        for (final MapEntry(:key, :value) in values.entries)
          if (!_knownKeys.contains(key)) key: value,
      }),
    );
  }

  // Значение необязательного ключа или `null`, если оно пусто.
  static String? _filled(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  // Ключи, которые читаются в поля, и `paragraphs` самого файла.
  static const Set<String> _knownKeys = {
    'type',
    'abbreviation',
    'name',
    'language',
    'direction',
    'script',
    'license',
    'copyright',
    'description',
    'source',
    'source_url',
    'version',
    'created',
    'catalog',
    'catalog_id',
    'chapter_word',
    'chapter_word_psalms',
    'numbering',
    'paragraphs',
    'generator',
  };

  /// Тип модуля: `type`.
  final ModuleType type;

  /// Аббревиатура, с которой модуль ставится: `abbreviation`.
  final String abbreviation;

  /// Название на языке модуля: `name`.
  final String name;

  /// Язык, самый короткий тег BCP 47; неизвестен — `und`: `language`.
  final String language;

  /// Направление письма: `direction`.
  final WritingDirection direction;

  /// Письменность ISO 15924 (`Cyrl`, `Hebr`): `script`.
  final String? script;

  /// Лицензия (`PD`, `CC-BY-4.0`, `redistributable`, `unknown`): `license`.
  final String license;

  /// Правообладатель и копирайт как у источника: `copyright`.
  final String? copyright;

  /// Описание модуля: `description`.
  final String? description;

  /// Источник (`ebible:<translationId>`): `source`.
  final String? source;

  /// Страница источника: `source_url`.
  final String? sourceUrl;

  /// Версия модуля: `version`.
  final String? version;

  /// Дата записи файла `YYYY-MM-DD`: `created`.
  final String? created;

  /// Каталог, из которого модуль; у своих файлов нет: `catalog`.
  final String? catalog;

  /// Id модуля в каталоге: `catalog_id`.
  final String? catalogId;

  /// Слово «Глава» модуля: `chapter_word`.
  final String? chapterWord;

  /// Слово «Псалом» модуля: `chapter_word_psalms`.
  final String? chapterWordPsalms;

  /// Нумерация толкований и ссылок (`eng`, `rso`): `numbering`.
  final String? numbering;

  /// Кто записал файл (`catalog_builder 0.1.0`): `generator`.
  final String? generator;

  /// Незнакомые ключи `meta` как есть.
  final Map<String, String> extra;

  /// Пары `meta`: известные ключи в порядке описания формата, затем [extra].
  ///
  /// Необязательные поля без значения (`null`, пустые, из пробелов) не
  /// пишутся.
  Map<String, String> toValues() {
    final values = <String, String>{
      'type': typeValue(type),
      'abbreviation': abbreviation,
      'name': name,
      'language': language,
      'direction': direction.name,
      'script': ?_filled(script),
      'license': license,
      'copyright': ?_filled(copyright),
      'description': ?_filled(description),
      'source': ?_filled(source),
      'source_url': ?_filled(sourceUrl),
      'version': ?_filled(version),
      'created': ?_filled(created),
      'catalog': ?_filled(catalog),
      'catalog_id': ?_filled(catalogId),
      'chapter_word': ?_filled(chapterWord),
      'chapter_word_psalms': ?_filled(chapterWordPsalms),
      'numbering': ?_filled(numbering),
      'generator': ?_filled(generator),
    };
    for (final MapEntry(:key, :value) in extra.entries) {
      if (!_knownKeys.contains(key)) {
        values.putIfAbsent(key, () => value);
      }
    }

    return values;
  }

  /// Копия описания с другой аббревиатурой.
  ModuleMeta copyWith({String? abbreviation}) => ModuleMeta(
    type: type,
    abbreviation: abbreviation ?? this.abbreviation,
    name: name,
    language: language,
    direction: direction,
    script: script,
    license: license,
    copyright: copyright,
    description: description,
    source: source,
    sourceUrl: sourceUrl,
    version: version,
    created: created,
    catalog: catalog,
    catalogId: catalogId,
    chapterWord: chapterWord,
    chapterWordPsalms: chapterWordPsalms,
    numbering: numbering,
    generator: generator,
    extra: extra,
  );

  @override
  bool operator ==(Object other) {
    if (other is! ModuleMeta) {
      return false;
    }
    final mine = toValues();
    final theirs = other.toValues();
    if (mine.length != theirs.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in mine.entries) {
      if (theirs[key] != value) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    final values = toValues();
    final keys = values.keys.toList()..sort();

    return Object.hashAll([for (final key in keys) (key, values[key])]);
  }

  @override
  String toString() => 'ModuleMeta(${toValues()})';
}
