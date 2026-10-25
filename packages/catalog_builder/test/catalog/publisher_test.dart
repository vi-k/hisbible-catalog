import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:test/test.dart';

void main() {
  const repo = 'vi-k/hisbible-catalog';
  late List<List<String>> commands;
  late Map<String, ProcessResult> answers;

  setUp(() {
    commands = [];
    answers = {};
  });

  // Ответ `gh` на команду, чьё начало есть в [answers]; иначе успех.
  Future<ProcessResult> gh(String executable, List<String> arguments) async {
    commands.add([executable, ...arguments]);
    final command = arguments.take(3).join(' ');

    return answers[command] ?? ProcessResult(0, 0, '', '');
  }

  ProcessResult notFound() => ProcessResult(0, 1, '', 'release not found\n');

  test('upload creates a missing pre-release once', () async {
    answers['release view sources-2026-11-01'] = notFound();
    final publisher = GhPublisher(run: gh);
    final file = File('/tmp/work/sources/aaa-2026-09-01_usfm.zip');

    final first = await publisher.upload(
      'sources-2026-11-01',
      file,
      prerelease: true,
    );
    await publisher.upload(
      'sources-2026-11-01',
      File('/tmp/work/sources/bbb-2026-09-01_usfm.zip'),
      prerelease: true,
    );

    expect(
      first,
      Uri.parse(
        'https://github.com/vi-k/hisbible-catalog/releases/download/'
        'sources-2026-11-01/aaa-2026-09-01_usfm.zip',
      ),
    );
    expect(commands, [
      [
        'gh',
        'release',
        'view',
        'sources-2026-11-01',
        '--repo',
        repo,
        '--json',
        'assets',
      ],
      [
        'gh',
        'release',
        'create',
        'sources-2026-11-01',
        '--repo',
        repo,
        '--title',
        'sources-2026-11-01',
        '--notes',
        '',
        '--prerelease',
      ],
      [
        'gh',
        'release',
        'upload',
        'sources-2026-11-01',
        '/tmp/work/sources/aaa-2026-09-01_usfm.zip',
        '--repo',
        repo,
        '--clobber',
      ],
      [
        'gh',
        'release',
        'upload',
        'sources-2026-11-01',
        '/tmp/work/sources/bbb-2026-09-01_usfm.zip',
        '--repo',
        repo,
        '--clobber',
      ],
    ]);
  });

  test('upload to an existing release does not create it', () async {
    answers['release view build-2026-11-01'] = ProcessResult(
      0,
      0,
      '{"assets":[]}',
      '',
    );
    final publisher = GhPublisher(run: gh);

    await publisher.upload(
      'build-2026-11-01',
      File('/tmp/work/modules/aaa-2026-09-01.hb'),
    );

    expect(commands, [
      [
        'gh',
        'release',
        'view',
        'build-2026-11-01',
        '--repo',
        repo,
        '--json',
        'assets',
      ],
      [
        'gh',
        'release',
        'upload',
        'build-2026-11-01',
        '/tmp/work/modules/aaa-2026-09-01.hb',
        '--repo',
        repo,
        '--clobber',
      ],
    ]);
  });

  test('a new build release is not a pre-release', () async {
    answers['release view build-2026-11-01'] = notFound();
    final publisher = GhPublisher(run: gh);

    await publisher.upload('build-2026-11-01', File('/tmp/a.hb'));

    expect(commands[1], [
      'gh',
      'release',
      'create',
      'build-2026-11-01',
      '--repo',
      repo,
      '--title',
      'build-2026-11-01',
      '--notes',
      '',
    ]);
  });

  test('assets and their count come from release view', () async {
    answers['release view fonts'] = ProcessResult(
      0,
      0,
      '{"assets":[{"name":"A.ttf","size":12,"state":"uploaded"},'
          '{"name":"B.ttf","size":34}]}',
      '',
    );
    answers['release view build-2026-11-01'] = notFound();
    final publisher = GhPublisher(run: gh);

    expect(await publisher.assets('fonts'), {'A.ttf': 12, 'B.ttf': 34});
    expect(await publisher.assetCount('fonts'), 2);
    expect(await publisher.assetCount('build-2026-11-01'), 0);
    expect(commands.first, [
      'gh',
      'release',
      'view',
      'fonts',
      '--repo',
      repo,
      '--json',
      'assets',
    ]);
  });

  test('deleteAsset runs delete-asset without a prompt', () async {
    await GhPublisher(run: gh)
        .deleteAsset('build-2026-11-01', 'aaa-2026-09-01.hb');

    expect(commands, [
      [
        'gh',
        'release',
        'delete-asset',
        'build-2026-11-01',
        'aaa-2026-09-01.hb',
        '--repo',
        repo,
        '--yes',
      ],
    ]);
  });

  test('a failed gh command is a PublishException', () async {
    answers['release view build-2026-11-01'] = ProcessResult(
      0,
      1,
      '',
      'HTTP 401: Bad credentials',
    );
    answers['release delete-asset build-2026-11-01'] = ProcessResult(
      0,
      1,
      '',
      'HTTP 403: Resource not accessible by integration',
    );
    final publisher = GhPublisher(run: gh);

    await expectLater(
      publisher.assets('build-2026-11-01'),
      throwsA(isA<PublishException>()),
    );
    await expectLater(
      publisher.deleteAsset('build-2026-11-01', 'x.hb'),
      throwsA(isA<PublishException>()),
    );
  });

  test('deleting a file that is already gone succeeds', () async {
    answers['release delete-asset build-2026-11-01'] = ProcessResult(
      0,
      1,
      '',
      'asset x.hb not found in release build-2026-11-01\n',
    );
    answers['release delete-asset build-2026-10-01'] = ProcessResult(
      0,
      1,
      '',
      'release not found\n',
    );
    final publisher = GhPublisher(run: gh);

    await publisher.deleteAsset('build-2026-11-01', 'x.hb');
    await publisher.deleteAsset('build-2026-10-01', 'y.hb');

    expect(commands, hasLength(2));
  });

  test('dry run publisher records and publishes nothing', () async {
    final publisher = DryRunPublisher();

    final url = await publisher.upload(
      'sources-2026-11-01',
      File('/tmp/aaa_usfm.zip'),
      prerelease: true,
    );
    await publisher.deleteAsset('build-2026-10-01', 'aaa.hb');

    expect(
      url.toString(),
      'https://github.com/vi-k/hisbible-catalog/releases/download/'
      'sources-2026-11-01/aaa_usfm.zip',
    );
    expect(publisher.uploads, ['sources-2026-11-01/aaa_usfm.zip']);
    expect(publisher.deletes, ['build-2026-10-01/aaa.hb']);
    expect(await publisher.assetCount('sources-2026-11-01'), 0);
    expect(await publisher.assets('fonts'), isEmpty);
  });

  test('release asset address round trips', () {
    final url = releaseAssetUrl('build-2026-11-01', 'aaa-2026-09-01.hb');

    expect(releaseAssetOf(url.toString()), (
      release: 'build-2026-11-01',
      asset: 'aaa-2026-09-01.hb',
    ));
    expect(releaseAssetOf('https://example.org/aaa.hb'), isNull);
  });
}
