import 'dart:convert';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  const russyn = IndexModule(
    id: 'russyn',
    type: 'bible',
    abbreviation: 'russyn',
    name: 'Синодальный перевод',
    description: 'Русская Библия',
    language: 'ru',
    languageName: 'Русский',
    languageNameEnglish: 'Russian',
    script: 'Cyrl',
    direction: WritingDirection.ltr,
    license: 'PD',
    copyright: 'Public Domain',
    books: (ot: 39, nt: 27, dc: 0),
    size: 4567890,
    sha256: 'aa',
    url:
        'https://github.com/vi-k/hisbible-catalog/releases/download/'
        'build-2026-11-01/russyn-2025-03-04.hb',
    version: '2025-03-04',
    moduleFormat: 1,
  );
  const arb = IndexModule(
    id: 'arb-vd',
    type: 'bible',
    abbreviation: 'AVD',
    name: 'Van Dyck',
    language: 'ar',
    languageName: 'العربية',
    languageNameEnglish: 'Arabic',
    script: 'Arab',
    direction: WritingDirection.rtl,
    license: 'redistributable',
    books: (ot: 39, nt: 27, dc: 7),
    size: 1,
    sha256: 'bb',
    url: 'https://example.org/arb-vd.hb',
    version: '2024-01-02',
    moduleFormat: 1,
  );
  const index = CatalogIndex(
    format: 1,
    catalog: 'hisbible',
    name: 'HisBible',
    updated: '2026-11-01',
    modules: [arb, russyn],
    fonts: {
      'Ethi': IndexFont(
        family: 'Noto Sans Ethiopic',
        license: 'OFL-1.1',
        size: 512345,
        sha256: 'cc',
        url:
            'https://github.com/vi-k/hisbible-catalog/releases/download/'
            'fonts/NotoSansEthiopic-Regular.ttf',
      ),
    },
    withdrawn: [
      WithdrawnModule(
        id: 'xyz',
        abbreviation: 'xyz',
        name: 'Gone',
        since: '2026-12-01',
      ),
    ],
  );

  test('index round trips', () {
    final json = index.toJson();

    expect(CatalogIndex.parse(json), index);
    expect(CatalogIndex.parse(json).toJson(), json);
    expect(json, startsWith('{\n  "format": 1,\n  "catalog": "hisbible",'));
    expect(json, endsWith('}\n'));
    final unsorted = CatalogIndex(
      format: 1,
      catalog: 'hisbible',
      name: 'HisBible',
      updated: '2026-11-01',
      modules: const [russyn, arb],
      fonts: index.fonts,
      withdrawn: index.withdrawn,
    );
    expect(unsorted.toJson(), json, reason: 'modules are sorted by id');

    final root = jsonDecode(json) as Map<String, Object?>;
    expect(root.keys, [
      'format',
      'catalog',
      'name',
      'updated',
      'modules',
      'fonts',
      'withdrawn',
    ]);
    final modules = root['modules']! as List<Object?>;
    expect((modules.last! as Map<String, Object?>).keys, [
      'id',
      'type',
      'abbreviation',
      'name',
      'description',
      'language',
      'languageName',
      'languageNameEnglish',
      'script',
      'direction',
      'license',
      'copyright',
      'books',
      'size',
      'sha256',
      'url',
      'version',
      'moduleFormat',
    ]);
    final first = modules.first! as Map<String, Object?>;
    expect(first['direction'], 'rtl');
    expect(first['books'], {'ot': 39, 'nt': 27, 'dc': 7});
    expect(
      first.containsKey('description'),
      isFalse,
      reason: 'an empty field is not written',
    );
  });

  test('index parse skips unknown fields', () {
    final root = jsonDecode(index.toJson()) as Map<String, Object?>;
    root['future'] = {'x': 1};
    final modules = root['modules']! as List<Object?>;
    (modules.first! as Map<String, Object?>)['stars'] = 5;
    final fonts = root['fonts']! as Map<String, Object?>;
    (fonts['Ethi']! as Map<String, Object?>)['weight'] = 400;
    final withdrawn = root['withdrawn']! as List<Object?>;
    (withdrawn.first! as Map<String, Object?>)['why'] = 'gone';

    expect(
      CatalogIndex.parse(jsonEncode(root)),
      CatalogIndex.parse(index.toJson()),
    );
  });

  test('index without fonts and withdrawn reads them empty', () {
    final parsed = CatalogIndex.parse(
      '{"format": 1, "catalog": "hisbible", "name": "HisBible", '
      '"updated": "2026-11-01", "modules": []}',
    );

    expect(parsed.modules, isEmpty);
    expect(parsed.fonts, isEmpty);
    expect(parsed.withdrawn, isEmpty);
    expect(
      CatalogIndex.parse(CatalogIndex.empty().toJson()),
      CatalogIndex.empty(),
    );
  });

  test('index of another shape is a FormatException', () {
    expect(() => CatalogIndex.parse('[]'), throwsFormatException);
    expect(() => CatalogIndex.parse('{"format": 1}'), throwsFormatException);
    expect(
      () => CatalogIndex.parse(
        '{"format": 1, "catalog": "c", "name": "n", "updated": "u", '
        '"modules": [{"id": "x"}]}',
      ),
      throwsFormatException,
    );
  });

  test('sources lock round trips', () {
    const lock = SourcesLock({
      'b': LockedSource(
        id: 'b',
        updateDate: '2026-01-02',
        sha256: 'bb',
        release: 'sources-2026-11-01',
        asset: 'b-2026-01-02_usfm.zip',
        fetched: '2026-11-01',
      ),
      'a': LockedSource(
        id: 'a',
        updateDate: '2025-01-02',
        sha256: 'aa',
        release: 'sources-2026-11-01-2',
        asset: 'a-2025-01-02_usfm.zip',
        fetched: '2026-11-01',
      ),
    });
    final json = lock.toJson();

    expect(SourcesLock.parse(json), lock);
    expect(json.indexOf('"a"'), lessThan(json.indexOf('"b"')));
    expect(json, startsWith('{\n  "sources": {\n    "a": {\n'));
    expect(SourcesLock.parse('{"sources": {}, "x": 1}').entries, isEmpty);
    expect(() => SourcesLock.parse('{"sources": []}'), throwsFormatException);
  });

  test('fonts lock reads the scripts', () {
    final lock = FontsLock.parse('''
{"fonts": {"Ethi": {
  "family": "Noto Sans Ethiopic",
  "sourceUrl": "https://example.org/NotoSansEthiopic-Regular.ttf",
  "sha256": "cc", "license": "OFL-1.1",
  "asset": "NotoSansEthiopic-Regular.ttf", "note": "skipped"}}}
''');

    expect(lock.fonts.keys, ['Ethi']);
    final font = lock.fonts['Ethi']!;
    expect(font.script, 'Ethi');
    expect(font.family, 'Noto Sans Ethiopic');
    expect(font.sourceUrl, 'https://example.org/NotoSansEthiopic-Regular.ttf');
    expect(font.sha256, 'cc');
    expect(font.license, 'OFL-1.1');
    expect(font.asset, 'NotoSansEthiopic-Regular.ttf');
    expect(FontsLock.parse('{"fonts": {}}').fonts, isEmpty);
    expect(() => FontsLock.parse('{"fonts": 1}'), throwsFormatException);
  });
}
