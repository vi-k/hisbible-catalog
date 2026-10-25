import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Репозиторий каталога на GitHub.
const String catalogRepo = 'vi-k/hisbible-catalog';

/// Полный адрес файла [asset] выпуска [release] репозитория [repo].
Uri releaseAssetUrl(
  String release,
  String asset, {
  String repo = catalogRepo,
}) => Uri.parse('https://github.com/$repo/releases/download/$release/$asset');

/// Файл `asset` выпуска `release`.
typedef ReleaseAsset = ({String release, String asset});

/// Выпуск и файл по адресу [url] файла выпуска репозитория [repo]; адрес
/// другого вида — `null`.
ReleaseAsset? releaseAssetOf(String url, {String repo = catalogRepo}) {
  final prefix = 'https://github.com/$repo/releases/download/';
  if (!url.startsWith(prefix)) {
    return null;
  }
  final parts = url.substring(prefix.length).split('/');
  if (parts.length != 2 || parts.any((part) => part.isEmpty)) {
    return null;
  }

  return (release: parts[0], asset: parts[1]);
}

/// Куда сборка выкладывает файлы: выпуски репозитория каталога.
abstract interface class Publisher {
  /// Выкладывает [file] в выпуск [release] под его именем и возвращает
  /// адрес файла.
  ///
  /// Выпуска нет — он создаётся, как pre-release при [prerelease]. Файл
  /// с тем же именем заменяется.
  Future<Uri> upload(String release, File file, {bool prerelease = false});

  /// Удаляет файл [asset] из выпуска [release].
  Future<void> deleteAsset(String release, String asset);

  /// Сколько файлов в выпуске [release]; выпуска нет — 0.
  Future<int> assetCount(String release);

  /// Файлы выпуска [release]: имя → размер в байтах; выпуска нет — пусто.
  Future<Map<String, int>> assets(String release);
}

/// Команда `gh` не удалась.
final class PublishException implements Exception {
  /// Создаёт ошибку с текстом [message].
  const PublishException(this.message);

  /// Что не удалось.
  final String message;

  @override
  String toString() => 'PublishException: $message';
}

/// Запуск программы [executable] с аргументами [arguments];
/// по умолчанию — [Process.run].
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// [Publisher] через `gh release` репозитория [repo].
///
/// `gh` берёт права из `GH_TOKEN`.
final class GhPublisher implements Publisher {
  /// Создаёт выкладку в [repo]; [run] — свой запуск `gh`.
  GhPublisher({this.repo = catalogRepo, ProcessRunner? run})
    : _run = run ?? Process.run;

  /// Репозиторий `владелец/имя`.
  final String repo;

  final ProcessRunner _run;

  // Выпуски, о которых уже известно, что они есть.
  final _existing = <String>{};

  @override
  Future<Uri> upload(
    String release,
    File file, {
    bool prerelease = false,
  }) async {
    if (!_existing.contains(release) && (await _view(release)) == null) {
      await _gh([
        'release',
        'create',
        release,
        '--repo',
        repo,
        '--title',
        release,
        '--notes',
        '',
        if (prerelease) '--prerelease',
      ]);
      _existing.add(release);
    }
    await _gh([
      'release',
      'upload',
      release,
      file.path,
      '--repo',
      repo,
      '--clobber',
    ]);

    return releaseAssetUrl(release, p.basename(file.path), repo: repo);
  }

  @override
  Future<void> deleteAsset(String release, String asset) =>
      _gh(['release', 'delete-asset', release, asset, '--repo', repo, '--yes']);

  @override
  Future<int> assetCount(String release) async =>
      (await assets(release)).length;

  @override
  Future<Map<String, int>> assets(String release) async =>
      await _view(release) ?? const {};

  // Файлы выпуска по `gh release view`; выпуска нет — `null`.
  Future<Map<String, int>?> _view(String release) async {
    final arguments = [
      'release',
      'view',
      release,
      '--repo',
      repo,
      '--json',
      'assets',
    ];
    final result = await _run('gh', arguments);
    if (result.exitCode != 0) {
      if ('${result.stderr}'.contains('release not found')) {
        return null;
      }
      throw PublishException(_failure(arguments, result));
    }
    _existing.add(release);
    try {
      final root = jsonDecode('${result.stdout}') as Map<String, Object?>;

      return {
        for (final asset in root['assets']! as List<Object?>)
          if (asset case {'name': final String name, 'size': final int size})
            name: size,
      };
    } on Object catch (e) {
      throw PublishException(
        'gh ${arguments.join(' ')}: unexpected output: $e',
      );
    }
  }

  Future<void> _gh(List<String> arguments) async {
    final result = await _run('gh', arguments);
    if (result.exitCode != 0) {
      throw PublishException(_failure(arguments, result));
    }
  }

  static String _failure(List<String> arguments, ProcessResult result) =>
      'gh ${arguments.join(' ')}: exit ${result.exitCode}: '
      '${'${result.stderr}'.trim()}';
}

/// [Publisher] пробного прогона: ничего не выкладывает, а записывает,
/// что выложил бы.
///
/// Адреса — те же, что дал бы [GhPublisher]; выпуски всегда пусты.
final class DryRunPublisher implements Publisher {
  /// Выкладки по порядку: `<выпуск>/<файл>`.
  final uploads = <String>[];

  /// Удаления по порядку: `<выпуск>/<файл>`.
  final deletes = <String>[];

  @override
  Future<Uri> upload(
    String release,
    File file, {
    bool prerelease = false,
  }) async {
    final asset = p.basename(file.path);
    uploads.add('$release/$asset');

    return releaseAssetUrl(release, asset);
  }

  @override
  Future<void> deleteAsset(String release, String asset) async {
    deletes.add('$release/$asset');
  }

  @override
  Future<int> assetCount(String release) async => 0;

  @override
  Future<Map<String, int>> assets(String release) async => const {};
}
