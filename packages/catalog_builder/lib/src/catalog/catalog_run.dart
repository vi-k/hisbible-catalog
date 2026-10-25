import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/catalog/catalog_index.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/catalog/overrides.dart';
import 'package:catalog_builder/src/catalog/publisher.dart';
import 'package:catalog_builder/src/catalog/report.dart';
import 'package:catalog_builder/src/catalog/sources_lock.dart';
import 'package:catalog_builder/src/ebible/translations_csv.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;

/// Больше файлов в выпуске сборка не кладёт: у GitHub предел 1000.
const int releaseFileLimit = 900;

/// Выпуск со шрифтами письменностей.
const String fontsRelease = 'fonts';

/// Адрес архива USFM перевода [translationId] на eBible.org.
Uri ebibleSourceUrl(String translationId) =>
    Uri.parse('https://ebible.org/Scriptures/${translationId}_usfm.zip');

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

/// Итог прогона сборки: новый указатель, список исходников и отчёт.
final class CatalogRun {
  /// Создаёт итог прогона.
  const CatalogRun({
    required this.index,
    required this.lock,
    required this.report,
  });

  /// Новый указатель.
  final CatalogIndex index;

  /// Новый список своих копий исходников.
  final SourcesLock lock;

  /// Отчёт прогона.
  final BuildReport report;
}

/// Собирает каталог из переводов [translations] поверх прежнего указателя
/// [previous] и списка исходников [lock].
///
/// Порядок — раздел «Каталог: репозиторий, сборка, выпуски» плана:
/// 1. Сначала [publishFonts] по [fonts]: шрифт с чужой sha256 —
///    [CatalogBuildException], и модули не трогаются.
/// 2. Берутся переводы с `Redistributable` и `downloadable`, кроме
///    `exclude` [overrides], по `translationId`.
/// 3. Перевод, чья версия в [previous] и копия в [lock] того же
///    `UpdateDate`, остаётся без изменений.
/// 4. Новый или обновлённый: исходник — своя копия из [lock] того же
///    `UpdateDate` (sha256 сверяется) или архив eBible, который
///    выкладывается в `sources-<дата>` (pre-release) и попадает в [lock];
///    копия прежней даты тогда удаляется. Затем [buildModule]: [Built] —
///    файл в `build-<дата>`, запись в указателе, файл прежней версии
///    удаляется; [BuildFailed] или исходник не получен — прежняя запись
///    остаётся, причина в отчёте.
/// 5. Был в [previous], а сейчас не взят — уходит в `withdrawn` с датой
///    [now]; его файлы модуля и исходника удаляются, запись — из [lock].
///    Собранный снова уходит из `withdrawn`.
///
/// [limit] — не больше стольких новых и обновлённых за прогон; остальные
/// ждут следующего и названы в [BuildReport.waiting]. В выпуске не больше
/// [releaseFileLimit] файлов: дальше `build-<дата>-2`, `-3`… Файлы прогона
/// лежат в [work]: `sources/`, `modules/`, `fonts/`. Удаления идут в конце
/// прогона; неудачное удаление прогон не останавливает и попадает
/// в [BuildReport.problems].
Future<CatalogRun> runCatalogBuild({
  required List<EbibleTranslation> translations,
  required CatalogIndex previous,
  required SourcesLock lock,
  required Overrides overrides,
  required Fetcher fetcher,
  required Publisher publisher,
  required Directory work,
  required DateTime now,
  FontsLock fonts = FontsLock.empty,
  int? limit,
}) async {
  final date = isoDate(now);
  final fontSection = await publishFonts(
    fonts,
    fetcher: fetcher,
    publisher: publisher,
    work: work,
  );
  final taken = <String, EbibleTranslation>{};
  for (final t in translations) {
    if (t.translationId.isNotEmpty &&
        t.redistributable &&
        t.downloadable &&
        !overrides.exclude.contains(t.translationId)) {
      taken.putIfAbsent(t.translationId, () => t);
    }
  }
  final run = _Run(
    fetcher: fetcher,
    publisher: publisher,
    work: work,
    overrides: overrides,
    now: now,
    entries: Map.of(lock.entries),
  );
  final before = {for (final module in previous.modules) module.id: module};
  final modules = <String, IndexModule>{};
  final withdrawn = {
    for (final module in previous.withdrawn) module.id: module,
  };
  final built = <String>[];
  final unchanged = <String>[];
  final waiting = <String>[];
  final failed = <String, List<String>>{};
  final warnings = <String, List<String>>{};
  var attempts = 0;
  for (final id in taken.keys.toList()..sort()) {
    final t = taken[id]!;
    final old = before[id];
    if (old != null &&
        old.version == t.updateDate &&
        run.entries[id]?.updateDate == t.updateDate) {
      modules[id] = old;
      unchanged.add(id);
      continue;
    }
    if (limit != null && attempts >= limit) {
      if (old != null) {
        modules[id] = old;
      }
      waiting.add(id);
      continue;
    }
    attempts++;
    switch (await run.build(t)) {
      case (final IndexModule module, final List<String> moduleWarnings):
        modules[id] = module;
        built.add(id);
        if (moduleWarnings.isNotEmpty) {
          warnings[id] = moduleWarnings;
        }
        final file = old == null ? null : releaseAssetOf(old.url);
        if (file != null && old!.url != module.url) {
          run.deletions.add(file);
        }
      case (null, final List<String> reasons):
        if (old != null) {
          modules[id] = old;
        }
        failed[id] = reasons;
    }
  }
  final gone = <String>[];
  for (final old in previous.modules) {
    if (!taken.containsKey(old.id)) {
      gone.add(old.id);
      withdrawn[old.id] = WithdrawnModule(
        id: old.id,
        abbreviation: old.abbreviation,
        name: old.name,
        since: date,
      );
      final file = releaseAssetOf(old.url);
      if (file != null) {
        run.deletions.add(file);
      }
    }
  }
  for (final id in run.entries.keys.toList()) {
    if (!taken.containsKey(id)) {
      final source = run.entries.remove(id)!;
      run.deletions.add((release: source.release, asset: source.asset));
    }
  }
  withdrawn.removeWhere((id, _) => modules.containsKey(id));
  final problems = <String>[];
  for (final (:release, :asset) in run.deletions) {
    try {
      await publisher.deleteAsset(release, asset);
    } on Exception catch (e) {
      problems.add('cannot delete $asset from $release: $e');
    }
  }

  return CatalogRun(
    index: CatalogIndex(
      format: catalogIndexFormat,
      catalog: 'hisbible',
      name: 'HisBible',
      updated: date,
      modules: [for (final id in modules.keys.toList()..sort()) modules[id]!],
      fonts: fontSection,
      withdrawn: [
        for (final id in withdrawn.keys.toList()..sort()) withdrawn[id]!,
      ],
    ),
    lock: SourcesLock(Map.unmodifiable(run.entries)),
    report: BuildReport(
      date: date,
      built: built,
      unchanged: unchanged,
      withdrawn: gone..sort(),
      failed: failed,
      warnings: warnings,
      waiting: waiting,
      problems: problems,
    ),
  );
}

// Состояние одного прогона: выпуски, исходники и что удалить в конце.
final class _Run {
  _Run({
    required this.fetcher,
    required this.publisher,
    required this.work,
    required this.overrides,
    required this.now,
    required this.entries,
  }) : _sources = _Releases(publisher, 'sources-${isoDate(now)}'),
       _builds = _Releases(publisher, 'build-${isoDate(now)}');

  final Fetcher fetcher;
  final Publisher publisher;
  final Directory work;
  final Overrides overrides;
  final DateTime now;

  // Исходники по id; меняются по ходу прогона.
  final Map<String, LockedSource> entries;

  // Файлы выпусков, которые удаляются в конце прогона.
  final deletions = <({String release, String asset})>[];

  final _Releases _sources;
  final _Releases _builds;

  // Собирает и выкладывает модуль перевода [t]: запись указателя
  // и предупреждения либо `null` и причины.
  Future<(IndexModule?, List<String>)> build(EbibleTranslation t) async {
    final id = t.translationId;
    final asset = '$id-${t.updateDate}_usfm.zip';
    final source = File(p.join(work.path, 'sources', asset));
    final locked = entries[id];
    final own = locked != null && locked.updateDate == t.updateDate;
    final List<int> bytes;
    try {
      bytes = await fetcher.get(
        own
            ? releaseAssetUrl(locked.release, locked.asset)
            : ebibleSourceUrl(id),
      );
    } on Exception catch (e) {
      return (null, ['cannot fetch the source of $id: $e']);
    }
    final sha256 = crypto.sha256.convert(bytes).toString();
    if (own && sha256 != locked.sha256) {
      final copy = '${locked.release}/${locked.asset}';

      return (
        null,
        ['source copy $copy: sha256 $sha256, expected ${locked.sha256}'],
      );
    }
    source.parent.createSync(recursive: true);
    source.writeAsBytesSync(bytes);
    if (!own) {
      final release = await _sources.next();
      await publisher.upload(release, source, prerelease: true);
      if (locked != null &&
          (locked.release != release || locked.asset != asset)) {
        deletions.add((release: locked.release, asset: locked.asset));
      }
      entries[id] = LockedSource(
        id: id,
        updateDate: t.updateDate,
        sha256: sha256,
        release: release,
        asset: asset,
        fetched: isoDate(now),
      );
    }
    final outcome = buildModule(
      t,
      source,
      p.join(work.path, 'modules', '$id-${t.updateDate}$moduleExtension'),
      overrides: overrides,
      now: now,
    );
    switch (outcome) {
      case BuildFailed(:final reasons):
        return (null, reasons);
      case Built():
        final release = await _builds.next();
        final url = await publisher.upload(release, File(outcome.path));

        return (_entry(t, outcome, url), outcome.warnings);
    }
  }
}

// Запись указателя для собранного модуля [built] перевода [t] по адресу
// [url].
IndexModule _entry(EbibleTranslation t, Built built, Uri url) {
  final meta = built.meta;

  return IndexModule(
    id: t.translationId,
    type: 'bible',
    abbreviation: meta.abbreviation,
    name: meta.name,
    description: meta.description,
    language: meta.language,
    languageName: t.languageName,
    languageNameEnglish: t.languageNameInEnglish,
    script: meta.script ?? 'Zyyy',
    direction: meta.direction,
    license: meta.license,
    copyright: meta.copyright,
    books: built.books,
    size: built.size,
    sha256: built.sha256,
    url: url.toString(),
    version: t.updateDate,
    moduleFormat: formatVersion,
  );
}

// Выпуски одного вида за прогон: `<base>`, `<base>-2`, `<base>-3`…
// по [releaseFileLimit] файлов.
final class _Releases {
  _Releases(this._publisher, this._base);

  final Publisher _publisher;
  final String _base;

  var _part = 1;

  // Файлов в текущем выпуске: что там было плюс что добавил прогон.
  int? _count;

  String get _name => _part == 1 ? _base : '$_base-$_part';

  // Выпуск для следующего файла.
  Future<String> next() async {
    while (true) {
      final count = _count ??= await _publisher.assetCount(_name);
      if (count < releaseFileLimit) {
        _count = count + 1;

        return _name;
      }
      _part++;
      _count = null;
    }
  }
}
