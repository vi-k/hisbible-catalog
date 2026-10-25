// Классы неизменяемы: final и только final-поля. Аннотация @immutable
// живёт в package:meta, а его нет в списке пакетов проекта.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:convert';

import 'package:hisbible_format/hisbible_format.dart';

/// Версия формата указателя, поле `format`.
const int catalogIndexFormat = 1;

/// Указатель каталога `index/index.json`.
///
/// Поля и их смысл — раздел «Указатель» плана; незнакомые поля при чтении
/// пропускаются.
final class CatalogIndex {
  /// Создаёт указатель.
  const CatalogIndex({
    required this.format,
    required this.catalog,
    required this.name,
    required this.updated,
    required this.modules,
    this.fonts = const {},
    this.withdrawn = const [],
  });

  /// Пустой указатель каталога HisBible: первый прогон сборки.
  factory CatalogIndex.empty() => const CatalogIndex(
    format: catalogIndexFormat,
    catalog: 'hisbible',
    name: 'HisBible',
    updated: '',
    modules: [],
  );

  /// Читает указатель из JSON [json].
  ///
  /// `fonts` и `withdrawn` необязательны: нет — пусто. Не JSON, нет
  /// обязательного поля или у поля другой тип — [FormatException].
  factory CatalogIndex.parse(String json) {
    final root = _object(_decode(json), 'index');

    return CatalogIndex(
      format: _int(root, 'format'),
      catalog: _string(root, 'catalog'),
      name: _string(root, 'name'),
      updated: _string(root, 'updated'),
      modules: [
        for (final item in _list(root, 'modules'))
          IndexModule._parse(_object(item, 'module')),
      ],
      fonts: {
        for (final MapEntry(:key, :value) in _map(root, 'fonts').entries)
          key: IndexFont._parse(_object(value, 'font $key')),
      },
      withdrawn: [
        for (final item in _list(root, 'withdrawn', optional: true))
          WithdrawnModule._parse(_object(item, 'withdrawn module')),
      ],
    );
  }

  /// Версия формата указателя.
  final int format;

  /// Id каталога: `hisbible`.
  final String catalog;

  /// Название каталога.
  final String name;

  /// Дата сборки, `YYYY-MM-DD`.
  final String updated;

  /// Модули каталога.
  final List<IndexModule> modules;

  /// Шрифты по коду письменности ISO 15924.
  final Map<String, IndexFont> fonts;

  /// Отозванные модули.
  final List<WithdrawnModule> withdrawn;

  /// JSON указателя с отступом в два пробела и переводом строки в конце.
  ///
  /// Модули и отозванные идут по `id`, шрифты — по коду письменности.
  String toJson() {
    final modules = [...this.modules]..sort((a, b) => a.id.compareTo(b.id));
    final withdrawn = [...this.withdrawn]..sort((a, b) => a.id.compareTo(b.id));
    final scripts = fonts.keys.toList()..sort();

    return '${const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'catalog': catalog,
      'name': name,
      'updated': updated,
      'modules': [for (final module in modules) module._toJson()],
      'fonts': {for (final script in scripts) script: fonts[script]!._toJson()},
      'withdrawn': [for (final module in withdrawn) module._toJson()],
    })}\n';
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogIndex &&
      other.format == format &&
      other.catalog == catalog &&
      other.name == name &&
      other.updated == updated &&
      _listEquals(other.modules, modules) &&
      _mapEquals(other.fonts, fonts) &&
      _listEquals(other.withdrawn, withdrawn);

  @override
  int get hashCode => Object.hash(
    format,
    catalog,
    name,
    updated,
    Object.hashAll(modules),
    Object.hashAllUnordered(
      fonts.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(withdrawn),
  );
}

/// Модуль каталога в указателе.
final class IndexModule {
  /// Создаёт запись модуля.
  const IndexModule({
    required this.id,
    required this.type,
    required this.abbreviation,
    required this.name,
    required this.language,
    required this.languageName,
    required this.languageNameEnglish,
    required this.script,
    required this.direction,
    required this.license,
    required this.books,
    required this.size,
    required this.sha256,
    required this.url,
    required this.version,
    required this.moduleFormat,
    this.description,
    this.copyright,
  });

  factory IndexModule._parse(Map<String, Object?> json) {
    final books = _object(json['books'], 'books');

    return IndexModule(
      id: _string(json, 'id'),
      type: _string(json, 'type'),
      abbreviation: _string(json, 'abbreviation'),
      name: _string(json, 'name'),
      description: _optionalString(json, 'description'),
      language: _string(json, 'language'),
      languageName: _string(json, 'languageName'),
      languageNameEnglish: _string(json, 'languageNameEnglish'),
      script: _string(json, 'script'),
      direction: _string(json, 'direction') == 'rtl'
          ? WritingDirection.rtl
          : WritingDirection.ltr,
      license: _string(json, 'license'),
      copyright: _optionalString(json, 'copyright'),
      books: (
        ot: _int(books, 'ot'),
        nt: _int(books, 'nt'),
        dc: _int(books, 'dc'),
      ),
      size: _int(json, 'size'),
      sha256: _string(json, 'sha256'),
      url: _string(json, 'url'),
      version: _string(json, 'version'),
      moduleFormat: _int(json, 'moduleFormat'),
    );
  }

  /// Id модуля в каталоге: `translationId` eBible.
  final String id;

  /// Тип модуля, значение `meta` `type`: `bible`.
  final String type;

  /// Аббревиатура модуля.
  final String abbreviation;

  /// Название модуля.
  final String name;

  /// Описание модуля; `null` — нет.
  final String? description;

  /// Язык, тег BCP 47.
  final String language;

  /// Название языка на нём самом.
  final String languageName;

  /// Название языка по-английски.
  final String languageNameEnglish;

  /// Письменность, код ISO 15924.
  final String script;

  /// Направление письма.
  final WritingDirection direction;

  /// Лицензия, значение `meta` `license`.
  final String license;

  /// Копирайт; `null` — нет.
  final String? copyright;

  /// Число книг Ветхого, Нового Завета и неканонических.
  final ({int ot, int nt, int dc}) books;

  /// Размер файла модуля в байтах.
  final int size;

  /// SHA-256 файла модуля, 64 шестнадцатеричные цифры.
  final String sha256;

  /// Полный адрес файла модуля.
  final String url;

  /// Версия модуля: `UpdateDate` перевода.
  final String version;

  /// Версия формата файла модуля.
  final int moduleFormat;

  Map<String, Object?> _toJson() => {
    'id': id,
    'type': type,
    'abbreviation': abbreviation,
    'name': name,
    'description': ?description,
    'language': language,
    'languageName': languageName,
    'languageNameEnglish': languageNameEnglish,
    'script': script,
    'direction': direction.name,
    'license': license,
    'copyright': ?copyright,
    'books': {'ot': books.ot, 'nt': books.nt, 'dc': books.dc},
    'size': size,
    'sha256': sha256,
    'url': url,
    'version': version,
    'moduleFormat': moduleFormat,
  };

  @override
  bool operator ==(Object other) =>
      other is IndexModule &&
      other.id == id &&
      other.type == type &&
      other.abbreviation == abbreviation &&
      other.name == name &&
      other.description == description &&
      other.language == language &&
      other.languageName == languageName &&
      other.languageNameEnglish == languageNameEnglish &&
      other.script == script &&
      other.direction == direction &&
      other.license == license &&
      other.copyright == copyright &&
      other.books == books &&
      other.size == size &&
      other.sha256 == sha256 &&
      other.url == url &&
      other.version == version &&
      other.moduleFormat == moduleFormat;

  @override
  int get hashCode => Object.hash(id, version, sha256, url);
}

/// Шрифт письменности в указателе.
final class IndexFont {
  /// Создаёт запись шрифта.
  const IndexFont({
    required this.family,
    required this.license,
    required this.size,
    required this.sha256,
    required this.url,
  });

  factory IndexFont._parse(Map<String, Object?> json) => IndexFont(
    family: _string(json, 'family'),
    license: _string(json, 'license'),
    size: _int(json, 'size'),
    sha256: _string(json, 'sha256'),
    url: _string(json, 'url'),
  );

  /// Семейство шрифта.
  final String family;

  /// Лицензия шрифта, например `OFL-1.1`.
  final String license;

  /// Размер файла в байтах.
  final int size;

  /// SHA-256 файла, 64 шестнадцатеричные цифры.
  final String sha256;

  /// Полный адрес файла шрифта.
  final String url;

  Map<String, Object?> _toJson() => {
    'family': family,
    'license': license,
    'size': size,
    'sha256': sha256,
    'url': url,
  };

  @override
  bool operator ==(Object other) =>
      other is IndexFont &&
      other.family == family &&
      other.license == license &&
      other.size == size &&
      other.sha256 == sha256 &&
      other.url == url;

  @override
  int get hashCode => Object.hash(family, license, size, sha256, url);
}

/// Отозванный модуль в указателе.
final class WithdrawnModule {
  /// Создаёт запись отозванного модуля.
  const WithdrawnModule({
    required this.id,
    required this.abbreviation,
    required this.name,
    required this.since,
  });

  factory WithdrawnModule._parse(Map<String, Object?> json) => WithdrawnModule(
    id: _string(json, 'id'),
    abbreviation: _string(json, 'abbreviation'),
    name: _string(json, 'name'),
    since: _string(json, 'since'),
  );

  /// Id модуля в каталоге.
  final String id;

  /// Аббревиатура модуля.
  final String abbreviation;

  /// Название модуля.
  final String name;

  /// Дата отзыва, `YYYY-MM-DD`.
  final String since;

  Map<String, Object?> _toJson() => {
    'id': id,
    'abbreviation': abbreviation,
    'name': name,
    'since': since,
  };

  @override
  bool operator ==(Object other) =>
      other is WithdrawnModule &&
      other.id == id &&
      other.abbreviation == abbreviation &&
      other.name == name &&
      other.since == since;

  @override
  int get hashCode => Object.hash(id, abbreviation, name, since);
}

Object? _decode(String json) {
  try {
    return jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('index.json is not JSON: ${e.message}');
  }
}

Map<String, Object?> _object(Object? value, String what) {
  if (value is! Map<String, Object?>) {
    throw FormatException('index.json: $what is not an object');
  }

  return value;
}

Map<String, Object?> _map(Map<String, Object?> json, String key) =>
    json[key] == null ? const {} : _object(json[key], key);

List<Object?> _list(
  Map<String, Object?> json,
  String key, {
  bool optional = false,
}) {
  final value = json[key];
  if (value == null && optional) {
    return const [];
  }
  if (value is! List<Object?>) {
    throw FormatException('index.json: $key is not a list');
  }

  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('index.json: $key is not a string');
  }

  return value;
}

String? _optionalString(Map<String, Object?> json, String key) =>
    json[key] == null ? null : _string(json, key);

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('index.json: $key is not an integer');
  }

  return value;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }

  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length &&
    a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
