import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
/// "file": …, "sha256": …, "license": …, "asset": …}}}`; `file` можно
/// не писать, незнакомые поля при чтении пропускаются.
final class FontsLock {
  /// Создаёт список шрифтов.
  const FontsLock(this.fonts);

  /// Читает список шрифтов из JSON [json].
  ///
  /// Не JSON или другая форма — [FormatException]. Её же даёт запись,
  /// у которой `sha256` — не 64 строчные шестнадцатеричные цифры или имя
  /// `asset` не кончается на `-<первые 8 цифр sha256>.ttf`: файл шрифта
  /// с другой sha256 не должен занять имя прежнего в выпуске.
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
    this.file,
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

    final file = json['file'];
    if (file != null && file is! String) {
      throw FormatException('fonts.lock.json: $script.file is not a string');
    }
    final sha256 = field('sha256');
    if (!_sha256.hasMatch(sha256)) {
      throw FormatException('fonts.lock.json: $script.sha256 is not SHA-256');
    }
    final asset = field('asset');
    if (!asset.endsWith('-${sha256.substring(0, 8)}.ttf')) {
      throw FormatException(
        'fonts.lock.json: $script.asset must end with '
        '-${sha256.substring(0, 8)}.ttf',
      );
    }

    return LockedFont(
      script: script,
      family: field('family'),
      sourceUrl: field('sourceUrl'),
      file: file as String?,
      sha256: sha256,
      license: field('license'),
      asset: asset,
    );
  }

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Код письменности ISO 15924.
  final String script;

  /// Семейство шрифта.
  final String family;

  /// Откуда скачать файл шрифта или архив ZIP с ним (выпуски `notofonts`
  /// на GitHub раздают только архивы).
  final String sourceUrl;

  /// Путь файла шрифта внутри архива [sourceUrl]; `null` — по [sourceUrl]
  /// лежит сам шрифт.
  final String? file;

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
/// выпуска, sha256 — из [lock]. Новый файл кладётся в `<work>/fonts/`;
/// у записи с [LockedFont.file] он сперва достаётся из архива источника.
/// Файл с другой sha256 или архив без этого файла —
/// [CatalogBuildException].
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
    final source = await fetcher.get(Uri.parse(font.sourceUrl));
    final bytes = font.file == null ? source : _unzip(source, font);
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

// Файл [LockedFont.file] шрифта [font] из архива ZIP [zip].
List<int> _unzip(List<int> zip, LockedFont font) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip);
  } on Object catch (e) {
    throw CatalogBuildException(
      'font ${font.script} ${font.sourceUrl}: not a ZIP archive: $e',
    );
  }
  final file = archive.findFile(font.file!);
  final bytes = file?.isFile ?? false ? file!.readBytes() : null;
  if (bytes == null) {
    throw CatalogBuildException(
      'font ${font.script} ${font.sourceUrl}: no ${font.file} in archive',
    );
  }

  return bytes;
}
