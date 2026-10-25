import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/src/catalog/catalog_index.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/catalog/publisher.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

/// Выпуск со шрифтами письменностей.
const String fontsRelease = 'fonts';

/// Прогон сборки не может продолжаться: например, у шрифта чужая sha256.
final class CatalogBuildException implements Exception {
  /// Создаёт ошибку с текстом [message].
  const CatalogBuildException(this.message);

  /// Что случилось.
  final String message;

  @override
  String toString() => 'CatalogBuildException: $message';
}

/// Шрифты письменностей, `fonts/fonts.lock.json`.
///
/// Вид файла: `{"fonts": {"<код ISO 15924>": {"family": …, "sourceUrl": …,
/// "sha256": …, "license": …, "asset": …}}}`; незнакомые поля при чтении
/// пропускаются.
final class FontsLock {
  /// Создаёт список шрифтов.
  const FontsLock(this.fonts);

  /// Читает список шрифтов из JSON [json].
  ///
  /// Не JSON или другая форма — [FormatException].
  factory FontsLock.parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('fonts.lock.json is not JSON: ${e.message}');
    }
    final fonts = root is Map<String, Object?>
        ? root['fonts'] ?? const <String, Object?>{}
        : null;
    if (fonts is! Map<String, Object?>) {
      throw const FormatException('fonts.lock.json: fonts is not an object');
    }

    return FontsLock({
      for (final MapEntry(:key, :value) in fonts.entries)
        key: LockedFont._parse(key, value),
    });
  }

  /// Шрифтов нет.
  static const empty = FontsLock({});

  /// Шрифты по коду письменности.
  final Map<String, LockedFont> fonts;
}

/// Шрифт письменности: откуда он берётся и как называется в выпуске.
final class LockedFont {
  /// Создаёт запись шрифта.
  const LockedFont({
    required this.script,
    required this.family,
    required this.sourceUrl,
    required this.sha256,
    required this.license,
    required this.asset,
  });

  factory LockedFont._parse(String script, Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('fonts.lock.json: $script is not an object');
    }
    String field(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('fonts.lock.json: $script.$key is not a string');
      }

      return value;
    }

    return LockedFont(
      script: script,
      family: field('family'),
      sourceUrl: field('sourceUrl'),
      sha256: field('sha256'),
      license: field('license'),
      asset: field('asset'),
    );
  }

  /// Код письменности ISO 15924.
  final String script;

  /// Семейство шрифта.
  final String family;

  /// Откуда скачать файл шрифта.
  final String sourceUrl;

  /// SHA-256 файла шрифта, 64 шестнадцатеричные цифры.
  final String sha256;

  /// Лицензия шрифта, например `OFL-1.1`.
  final String license;

  /// Имя файла в выпуске [fontsRelease].
  final String asset;
}

/// Выкладывает в выпуск `fonts` шрифты, которых там нет, проверив sha256
/// источника; возвращает раздел `fonts` указателя.
///
/// Шрифт, уже лежащий в выпуске, не скачивается: размер берётся из
/// выпуска, sha256 — из [lock]. Новый файл кладётся в `<work>/fonts/`.
/// Файл источника с другой sha256 — [CatalogBuildException].
Future<Map<String, IndexFont>> publishFonts(
  FontsLock lock, {
  required Fetcher fetcher,
  required Publisher publisher,
  required Directory work,
}) async {
  if (lock.fonts.isEmpty) {
    return const {};
  }
  final present = await publisher.assets(fontsRelease);
  final fonts = <String, IndexFont>{};
  for (final script in lock.fonts.keys.toList()..sort()) {
    final font = lock.fonts[script]!;
    final size = present[font.asset];
    if (size != null) {
      fonts[script] = IndexFont(
        family: font.family,
        license: font.license,
        size: size,
        sha256: font.sha256,
        url: releaseAssetUrl(fontsRelease, font.asset).toString(),
      );
      continue;
    }
    final bytes = await fetcher.get(Uri.parse(font.sourceUrl));
    final sha256 = crypto.sha256.convert(bytes).toString();
    if (sha256 != font.sha256) {
      throw CatalogBuildException(
        'font $script ${font.sourceUrl}: sha256 $sha256, '
        'expected ${font.sha256}',
      );
    }
    final file = File(p.join(work.path, 'fonts', font.asset));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    final url = await publisher.upload(fontsRelease, file);
    fonts[script] = IndexFont(
      family: font.family,
      license: font.license,
      size: bytes.length,
      sha256: sha256,
      url: url.toString(),
    );
  }

  return fonts;
}
