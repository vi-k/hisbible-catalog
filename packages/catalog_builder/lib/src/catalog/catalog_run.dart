import 'dart:io';
import 'dart:math' as math;

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/catalog/catalog_index.dart';
import 'package:catalog_builder/src/catalog/fetcher.dart';
import 'package:catalog_builder/src/catalog/fonts.dart';
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

/// Сколько раз выкладка файла повторяется после неудачи.
const int uploadRetries = 3;

/// Больше стольких неудачных выкладок — прогон не берёт новых сборок
/// и завершается с тем, что успел.
const int uploadFailureLimit = 20;

/// Меньше стольких отзывов за прогон — не массовый отзыв, каким бы ни был
/// каталог.
const int massWithdrawalMinimum = 20;

/// Больше такой доли каталога, в процентах, и больше
/// [massWithdrawalMinimum] модулей прогон без `allowMassWithdrawal`
/// не отзывает.
const int massWithdrawalPercent = 5;

/// Каким должен быть `translationId`, чтобы стать именем файла и выпуска.
final translationIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Каким должен быть `UpdateDate`: `YYYY-MM-DD`.
final updateDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Адрес архива USFM перевода [translationId] на eBible.org.
Uri ebibleSourceUrl(String translationId) =>
    Uri.parse('https://ebible.org/Scriptures/${translationId}_usfm.zip');

/// Итог прогона сборки: новый указатель, список исходников, отчёт и файлы
/// выпусков к удалению.
final class CatalogRun {
  /// Создаёт итог прогона.
  const CatalogRun({
    required this.index,
    required this.lock,
    required this.report,
    this.deletions = const [],
  });

  /// Новый указатель.
  final CatalogIndex index;

  /// Новый список своих копий исходников.
  final SourcesLock lock;

  /// Отчёт прогона.
  final BuildReport report;

  /// Файлы выпусков к удалению следующим прогоном: на них новый указатель
  /// и список исходников больше не ссылаются, плюс прежние удаления, которые
  /// не удались. Пишутся в `sources/pending-deletions.json` рядом
  /// с указателем.
  final List<ReleaseAsset> deletions;
}

/// Собирает каталог из переводов [translations] поверх прежнего указателя
/// [previous] и списка исходников [lock].
///
/// Порядок — раздел «Каталог: репозиторий, сборка, выпуски» плана:
/// 0. Удаляются файлы [pending], записанные прошлым прогоном, кроме тех,
///    на которые снова ссылается [previous] или [lock]: к этому времени
///    указатель без них давно отправлен, и кэш raw.githubusercontent.com
///    его уже отдаёт. Неудачные удаления переходят в
///    [CatalogRun.deletions].
/// 1. Сначала [publishFonts] по [fonts]: шрифт с чужой sha256 —
///    [CatalogBuildException], и модули не трогаются.
/// 2. Берутся переводы с `Redistributable` и `downloadable`, кроме
///    `exclude` [overrides], по `translationId`. Строка, чей `translationId`
///    не подходит под [translationIdPattern] или `UpdateDate` — под
///    [updateDatePattern], пропускается и попадает в
///    [BuildReport.skipped]; прежние запись и копия такого перевода
///    остаются как есть.
/// 3. Перевод, чья версия в [previous] и копия в [lock] того же
///    `UpdateDate`, остаётся без изменений.
/// 4. Новый или обновлённый: исходник — своя копия из [lock] того же
///    `UpdateDate` (sha256 сверяется) или архив eBible, который
///    выкладывается в `sources-<дата>` (pre-release) и попадает в [lock];
///    копия прежней даты тогда идёт к удалению. Затем [buildModule]:
///    [Built] — файл в `build-<дата>`, запись в указателе, файл прежней
///    версии идёт к удалению; [BuildFailed] или исходник не получен —
///    прежняя запись остаётся, причина в отчёте.
/// 5. Был в [previous], а сейчас не взят — уходит в `withdrawn` с датой
///    [now]; его файлы модуля и исходника идут к удалению, запись —
///    из [lock]. Собранный снова уходит из `withdrawn`. Если так уходят
///    больше [massWithdrawalMinimum] модулей и больше
///    [massWithdrawalPercent] % [previous], а [allowMassWithdrawal] нет,
///    никто не отзывается и ничего не идёт к удалению, а
///    [BuildReport.withdrawalRefused] говорит почему.
///
/// Сначала идут новые и обновлённые, потом те, чья копия в [lock] уже
/// того же `UpdateDate`, а сборка в прошлый раз не прошла: вечно
/// несобираемые не съедают [limit]. [limit] — не больше стольких сборок
/// за прогон; остальные ждут следующего и названы в
/// [BuildReport.waiting]. В выпуске не больше [releaseFileLimit] файлов:
/// дальше `build-<дата>-2`, `-3`…
///
/// Неудачная выкладка повторяется до [uploadRetries] раз с паузой [pause]
/// 2, 4, 8 секунд. Не вышло — перевод не собран, причина в отчёте,
/// прежняя запись остаётся; невыложенный исходник не попадает в [lock].
/// Больше [uploadFailureLimit] таких неудач — остальные ждут следующего
/// прогона, а прогон завершается как обычно. Выпуск для файла узнаётся
/// (`assetCount`) под теми же повторами. [RateLimitException] не
/// повторяется: перевод не собран, остальные ждут следующего прогона.
/// После [deadline] по часам [clock] новые переводы тоже не берутся.
/// Любая другая ошибка сборки перевода — тоже только его неудача: прогон
/// всегда доходит до указателя, списка исходников и отчёта.
///
/// Удаления этого прогона не делаются сразу: они — в
/// [CatalogRun.deletions], для следующего прогона. Файлы прогона лежат
/// в [work]: `sources/`, `modules/`, `fonts/`; без [keepFiles] архив
/// исходника удаляется из [work] после сборки, а файл модуля — сразу
/// после выкладки.
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
  List<ReleaseAsset> pending = const [],
  int? limit,
  bool allowMassWithdrawal = false,
  DateTime? deadline,
  DateTime Function() clock = _utcNow,
  bool keepFiles = false,
  Future<void> Function(Duration) pause = _sleep,
}) async {
  final date = isoDate(now);
  final cleanup = await _applyPending(pending, previous, lock, publisher);
  final fontSection = await publishFonts(
    fonts,
    fetcher: fetcher,
    publisher: publisher,
    work: work,
  );
  final taken = <String, EbibleTranslation>{};
  final skipped = <String, String>{};
  for (final t in translations) {
    if (!t.redistributable ||
        !t.downloadable ||
        overrides.exclude.contains(t.translationId)) {
      continue;
    }
    if (_rowProblem(t) case final problem?) {
      skipped[t.translationId] = problem;
    } else {
      taken.putIfAbsent(t.translationId, () => t);
    }
  }
  // Пропущенный перевод не отзывается: его прежние запись и копия ждут
  // исправленной строки.
  final held = {
    for (final id in skipped.keys)
      if (!taken.containsKey(id)) id,
  };
  final run = _Run(
    fetcher: fetcher,
    publisher: publisher,
    work: work,
    overrides: overrides,
    now: now,
    entries: Map.of(lock.entries),
    keepFiles: keepFiles,
    pause: pause,
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
  final fresh = <EbibleTranslation>[];
  final retries = <EbibleTranslation>[];
  for (final id in taken.keys.toList()..sort()) {
    final t = taken[id]!;
    final old = before[id];
    final copied = run.entries[id]?.updateDate == t.updateDate;
    if (old != null && old.version == t.updateDate && copied) {
      modules[id] = old;
      unchanged.add(id);
    } else {
      (copied ? retries : fresh).add(t);
    }
  }
  for (final id in held) {
    if (before[id] case final old?) {
      modules[id] = old;
    }
  }
  var attempts = 0;
  String? stopped;
  for (final t in [...fresh, ...retries]) {
    final id = t.translationId;
    final old = before[id];
    stopped ??=
        run.stopReason() ??
        (deadline != null && !clock().isBefore(deadline)
            ? 'Stopped at the deadline'
            : null);
    if ((limit != null && attempts >= limit) || stopped != null) {
      if (old != null) {
        modules[id] = old;
      }
      waiting.add(id);
      continue;
    }
    attempts++;
    (IndexModule?, List<String>) outcome;
    try {
      outcome = await run.build(t);
    } on Object catch (e) {
      // Ошибка, которой сборка не ждала, валит только этот перевод.
      outcome = (null, ['unexpected error: $e']);
    }
    switch (outcome) {
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
  stopped ??= run.stopReason();
  bool leaving(String id) => !taken.containsKey(id) && !held.contains(id);
  final leavers = [
    for (final old in previous.modules)
      if (leaving(old.id)) old,
  ];
  final withdrawalLimit = math.max(
    massWithdrawalMinimum,
    previous.modules.length * massWithdrawalPercent ~/ 100,
  );
  String? withdrawalRefused;
  final gone = <String>[];
  if (leavers.length > withdrawalLimit && !allowMassWithdrawal) {
    withdrawalRefused =
        'Withdrawal refused: ${leavers.length} modules would leave the '
        'catalog, more than the limit of $withdrawalLimit, so they all stay '
        'and nothing of theirs is deleted. If eBible really withdrew them, '
        'run the build again with --allow-mass-withdrawal';
    for (final old in leavers) {
      modules[old.id] = old;
    }
  } else {
    for (final old in leavers) {
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
    for (final id in run.entries.keys.toList()..sort()) {
      if (leaving(id)) {
        final source = run.entries.remove(id)!;
        run.deletions.add((release: source.release, asset: source.asset));
      }
    }
  }
  withdrawn.removeWhere((id, _) => modules.containsKey(id));
  final deletions = {...cleanup.failed, ...run.deletions}.toList();

  return CatalogRun(
    index: _indexOf(
      previous,
      date: date,
      modules: [for (final id in modules.keys.toList()..sort()) modules[id]!],
      fonts: fontSection,
      withdrawn: [
        for (final id in withdrawn.keys.toList()..sort()) withdrawn[id]!,
      ],
    ),
    lock: SourcesLock(Map.unmodifiable(run.entries)),
    report: BuildReport(
      date: date,
      built: built..sort(),
      unchanged: unchanged,
      withdrawn: gone..sort(),
      failed: failed,
      warnings: warnings,
      waiting: waiting..sort(),
      skipped: skipped,
      deletions: [
        for (final (:release, :asset) in deletions) '$release/$asset',
      ],
      deleted: cleanup.deleted,
      deletionProblems: cleanup.problems,
      stopped: stopped,
      withdrawalRefused: withdrawalRefused,
    ),
    deletions: List.unmodifiable(deletions),
  );
}

// Что не так со строкой перевода [t], которую сборка взяла бы, или `null`.
String? _rowProblem(EbibleTranslation t) {
  if (!translationIdPattern.hasMatch(t.translationId)) {
    return 'translationId "${t.translationId}" is not letters, digits, '
        '_ and -';
  }
  if (!updateDatePattern.hasMatch(t.updateDate)) {
    return 'UpdateDate "${t.updateDate}" is not YYYY-MM-DD';
  }

  return null;
}

// Новый указатель; если модули, шрифты и отозванные те же, что в
// [previous], дата `updated` остаётся прежней: у файла тот же ETag, и
// приложения не качают его заново.
CatalogIndex _indexOf(
  CatalogIndex previous, {
  required String date,
  required List<IndexModule> modules,
  required Map<String, IndexFont> fonts,
  required List<WithdrawnModule> withdrawn,
}) {
  CatalogIndex index(String updated) => CatalogIndex(
    format: catalogIndexFormat,
    catalog: 'hisbible',
    name: 'HisBible',
    updated: updated,
    modules: modules,
    fonts: fonts,
    withdrawn: withdrawn,
  );
  if (previous.updated.isNotEmpty) {
    final same = index(previous.updated);
    if (same.toJson() == previous.toJson()) {
      return same;
    }
  }

  return index(date);
}

// Итог удаления файлов прошлого прогона.
typedef _Cleanup = ({
  List<String> deleted,
  List<String> problems,
  List<ReleaseAsset> failed,
});

// Удаляет файлы [pending], на которые не ссылаются ни [index], ни [lock]:
// удалённые, причины неудач и неудавшиеся файлы. Файл, на который снова
// ссылаются, не удаляется и из списка уходит.
Future<_Cleanup> _applyPending(
  List<ReleaseAsset> pending,
  CatalogIndex index,
  SourcesLock lock,
  Publisher publisher,
) async {
  final used = <ReleaseAsset>{
    for (final module in index.modules) ?releaseAssetOf(module.url),
    for (final font in index.fonts.values) ?releaseAssetOf(font.url),
    for (final source in lock.entries.values)
      (release: source.release, asset: source.asset),
  };
  final deleted = <String>[];
  final problems = <String>[];
  final failed = <ReleaseAsset>[];
  for (final file in {...pending}) {
    if (used.contains(file)) {
      continue;
    }
    try {
      await publisher.deleteAsset(file.release, file.asset);
      deleted.add('${file.release}/${file.asset}');
    } on Exception catch (e) {
      problems.add('cannot delete ${file.asset} from ${file.release}: $e');
      failed.add(file);
    }
  }

  return (deleted: deleted, problems: problems, failed: failed);
}

// Состояние одного прогона: выпуски, исходники и файлы к удалению.
final class _Run {
  _Run({
    required this.fetcher,
    required this.publisher,
    required this.work,
    required this.overrides,
    required this.now,
    required this.entries,
    required this.keepFiles,
    required this.pause,
  }) : _sources = _Releases(publisher, 'sources-${isoDate(now)}'),
       _builds = _Releases(publisher, 'build-${isoDate(now)}');

  final Fetcher fetcher;
  final Publisher publisher;
  final Directory work;
  final Overrides overrides;
  final DateTime now;

  // Оставлять ли в [work] архивы и модули после выкладки.
  final bool keepFiles;

  // Пауза перед повтором выкладки.
  final Future<void> Function(Duration) pause;

  // Сколько файлов не выложилось и после повторов.
  int uploadFailures = 0;

  // GitHub ответил, что предел запросов исчерпан.
  bool rateLimited = false;

  // Почему прогон больше не берёт переводов, или `null`.
  String? stopReason() {
    if (rateLimited) {
      return 'Stopped: the GitHub API rate limit is exhausted';
    }
    if (uploadFailures > uploadFailureLimit) {
      return 'Stopped early: $uploadFailures uploads failed';
    }

    return null;
  }

  // Исходники по id; меняются по ходу прогона.
  final Map<String, LockedSource> entries;

  // Файлы выпусков, на которые больше ничто не ссылается.
  final deletions = <ReleaseAsset>[];

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
      final (:release, :url, :problem) = await _upload(
        _sources,
        source,
        prerelease: true,
      );
      if (release == null || url == null) {
        _remove(source);

        return (null, [problem]);
      }
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
    // Архив выложен или уже лежит в выпуске; после сборки он не нужен.
    _remove(source);
    switch (outcome) {
      case BuildFailed(:final reasons):
        return (null, reasons);
      case Built():
        final file = File(outcome.path);
        final (:url, :problem, release: _) = await _upload(_builds, file);
        _remove(file);

        return url == null
            ? (null, [problem])
            : (_entry(t, outcome, url), outcome.warnings);
    }
  }

  // Выкладывает [file] в очередной выпуск [releases]; выпуск узнаётся
  // и файл выкладывается с повторами до [uploadRetries] раз. Удалось —
  // выпуск и адрес; нет — `null` и причина. [RateLimitException]
  // не повторяется и ставит [rateLimited].
  Future<({String? release, Uri? url, String problem})> _upload(
    _Releases releases,
    File file, {
    bool prerelease = false,
  }) async {
    String? release;
    for (var attempt = 0; ; attempt++) {
      try {
        release ??= await releases.next();

        return (
          release: release,
          url: await publisher.upload(release, file, prerelease: prerelease),
          problem: '',
        );
      } on Exception catch (e) {
        final problem =
            'cannot upload ${p.basename(file.path)} to '
            '${release ?? releases.current}: $e';
        if (e is RateLimitException) {
          rateLimited = true;

          return (release: null, url: null, problem: problem);
        }
        if (attempt >= uploadRetries) {
          uploadFailures++;

          return (release: null, url: null, problem: problem);
        }
        await pause(Duration(seconds: 2 << attempt));
      }
    }
  }

  void _remove(File file) {
    if (!keepFiles && file.existsSync()) {
      file.deleteSync();
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

  // Выпуск, в который идёт следующий файл, если в нём есть место.
  String get current => _name;

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

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

DateTime _utcNow() => DateTime.now().toUtc();
