import 'dart:convert';
import 'dart:io';

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:catalog_builder/src/edition/spelling.dart';
import 'package:catalog_builder/src/text_helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hisbible_format/hisbible_format.dart';
import 'package:path/path.dart' as p;

/// Папка изданий в корне открытого репозитория: `editions/<id>/`.
const editionsDir = 'editions';

/// Издание: папка с `edition.json`, `usfm/` и `spelling.tsv`.
final class Edition {
  /// Создаёт издание из папки [dir] и полей её `edition.json`.
  const Edition({
    required this.dir,
    required this.id,
    required this.abbreviation,
    required this.name,
    required this.description,
    required this.language,
    required this.languageName,
    required this.languageNameEnglish,
    required this.script,
    required this.direction,
    required this.license,
    required this.copyright,
    required this.sourceUrl,
  });

  /// Папка издания.
  final Directory dir;

  /// Id модуля в каталоге.
  final String id;

  /// Аббревиатура перевода.
  final String abbreviation;

  /// Название перевода.
  final String name;

  /// Описание перевода.
  final String description;

  /// Код языка BCP 47.
  final String language;

  /// Название языка на нём самом.
  final String languageName;

  /// Название языка по-английски.
  final String languageNameEnglish;

  /// Код письменности ISO 15924.
  final String script;

  /// Направление письма: `ltr` или `rtl`.
  final String direction;

  /// Лицензия модуля.
  final String license;

  /// Правообладатель и условия.
  final String copyright;

  /// Страница источника.
  final String sourceUrl;
}

/// Читает издание из [dir]: нужны `edition.json` со всеми полями, папка
/// `usfm/` и `spelling.tsv`; чего-то нет — [FormatException].
Edition readEdition(Directory dir) {
  final file = File(p.join(dir.path, 'edition.json'));
  if (!file.existsSync()) {
    throw FormatException('${dir.path}: нет edition.json');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw FormatException('${file.path}: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('${file.path}: нужен объект JSON');
  }
  final json = decoded;
  final missing = <String>[];
  String field(String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    missing.add(key);

    return '';
  }

  final edition = Edition(
    dir: dir,
    id: field('id'),
    abbreviation: field('abbreviation'),
    name: field('name'),
    description: field('description'),
    language: field('language'),
    languageName: field('languageName'),
    languageNameEnglish: field('languageNameEnglish'),
    script: field('script'),
    direction: field('direction'),
    license: field('license'),
    copyright: field('copyright'),
    sourceUrl: field('sourceUrl'),
  );
  if (missing.isNotEmpty) {
    throw FormatException('${file.path}: нет полей ${missing.join(', ')}');
  }
  for (final path in [_usfmDir(dir).path, _spellingFile(dir).path]) {
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      throw FormatException('${dir.path}: нет ${p.basename(path)}');
    }
  }

  return edition;
}

/// Все издания папки [root]`/editions/`, по именам папок.
List<Edition> readEditions(Directory root) {
  final base = Directory(p.join(root.path, editionsDir));
  if (!base.existsSync()) {
    return const [];
  }
  final dirs = base.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  return [for (final dir in dirs) readEdition(dir)];
}

/// SHA-256 издания: по отсортированным путям и байтам всех файлов `usfm/`,
/// `spelling.tsv` и `edition.json`.
///
/// Меняется от любой правки файла и не зависит от порядка, в котором
/// файловая система отдаёт имена.
String editionDigest(Directory dir) {
  final files = <String, File>{
    'edition.json': File(p.join(dir.path, 'edition.json')),
    'spelling.tsv': _spellingFile(dir),
    for (final file in _usfmFiles(dir)) 'usfm/${p.basename(file.path)}': file,
  };
  final paths = files.keys.toList()..sort();
  final sink = _DigestSink();
  final input = crypto.sha256.startChunkedConversion(sink);
  for (final path in paths) {
    final bytes = files[path]!.readAsBytesSync();
    // Длина и разделитель не дают слить конец одного файла с началом другого.
    input
      ..add(utf8.encode('$path\u0000${bytes.length}\u0000'))
      ..add(bytes);
  }
  input.close();

  return sink.value.toString();
}

final class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// Итог сборки модуля из издания.
final class EditionOutcome {
  /// Создаёт итог собранного модуля.
  const EditionOutcome({
    required this.meta,
    required this.books,
    required this.verses,
    required this.replaced,
    required this.links,
    required this.schemes,
    required this.warnings,
  });

  /// Описание модуля, записанное в файл.
  final ModuleMeta meta;

  /// Число книг Ветхого, Нового Завета и неканонических.
  final ({int ot, int nt, int dc}) books;

  /// Число стихов в модуле.
  final int verses;

  /// Сколько слов заменила таблица написания.
  final int replaced;

  /// Счётчики ссылок из `\xt`.
  final XtStats links;

  /// Сколько книг в какой схеме нумерации.
  final Map<VerseScheme, int> schemes;

  /// Что сборка пропустила или выбросила.
  final List<String> warnings;

  /// Строка итога для `--edition`.
  String summary() {
    final schemeText = [
      for (final MapEntry(:key, :value) in schemes.entries)
        '${key.name} $value',
    ].join(', ');

    return 'verses $verses, books ${books.ot}/${books.nt}/${books.dc}, '
        'replaced $replaced, links ${links.linked}, '
        'unresolved ${links.unresolved}, schemes $schemeText';
  }
}

/// Собирает модуль Библии [outPath] из издания [edition].
///
/// Файлы `usfm/` проходят [applySpelling], разбираются [readUsfmBooks] и
/// пишутся в `<outPath>.part`; тот проверяется и встаёт на место [outPath].
/// Не годен модуль — [FormatException] со всеми причинами; файла [outPath]
/// и `.part` после неудачи нет, и при любой другой ошибке тоже.
Future<EditionOutcome> buildEdition(
  Edition edition,
  String outPath, {
  required String version,
  required DateTime now,
}) async {
  final spelling = parseSpellingTable(
    _spellingFile(edition.dir).readAsStringSync(),
  );
  var replaced = 0;
  var expectedVerses = 0;
  final sources = <UsfmSource>[];
  for (final file in _usfmFiles(edition.dir)) {
    final fixed = applySpelling(
      withoutBom(utf8.decode(file.readAsBytesSync())),
      spelling,
    );
    replaced += fixed.replaced;
    expectedVerses += _verseMarker.allMatches(fixed.text).length;
    sources.add((name: p.basename(file.path), bytes: utf8.encode(fixed.text)));
  }
  final read = readUsfmBooks(sources);
  if (read.books.isEmpty) {
    throw FormatException('${edition.id}: в usfm/ нет книг');
  }
  final meta = ModuleMeta(
    type: ModuleType.bible,
    abbreviation: edition.abbreviation,
    name: edition.name,
    language: edition.language,
    direction: edition.direction == 'rtl'
        ? WritingDirection.rtl
        : WritingDirection.ltr,
    script: edition.script,
    license: edition.license,
    copyright: edition.copyright,
    description: edition.description,
    source: 'edition:${edition.id}',
    sourceUrl: edition.sourceUrl,
    version: version,
    created: isoDate(now),
    catalog: 'hisbible',
    catalogId: edition.id,
    chapterWord: read.ordered(edition.language).chapterLabel,
    generator: 'catalog_builder $builderVersion',
  );

  final part = File('$outPath.part');
  var done = false;
  try {
    part.parent.createSync(recursive: true);
    final links = writeUsfmModule(part.path, meta, read);
    final check = _check(part.path, expectedVerses);
    // Незнакомый маркер и выброшенный кусок — потерянный текст: у издания
    // такого быть не должно, и разбор молча его выбрасывает.
    final reasons = [
      for (final warning in read.warnings)
        if (_lossWarning.hasMatch(warning)) warning,
      ...check.reasons,
    ];
    if (reasons.isNotEmpty) {
      throw FormatException(reasons.join('\n'));
    }
    part.renameSync(outPath);
    done = true;

    return EditionOutcome(
      meta: meta,
      books: check.books,
      verses: check.verses,
      replaced: replaced,
      links: links,
      schemes: check.schemes,
      warnings: read.warnings,
    );
  } finally {
    if (!done && part.existsSync()) {
      part.deleteSync();
    }
  }
}

// Начало стиха: `\v` и пробел.
final _verseMarker = RegExp(r'\\v\s');

// Предупреждение разбора о потерянном тексте.
final _lossWarning = RegExp(': (unknown markers|dropped fragments)');

// Остаток разметки в видимом тексте: `\` или `<` перед буквой.
final _leftover = RegExp(r'[\\<][A-Za-z]');

// Сколько мест с остатком разметки называет причина.
const _shownPlaces = 10;

Directory _usfmDir(Directory dir) => Directory(p.join(dir.path, 'usfm'));

File _spellingFile(Directory dir) => File(p.join(dir.path, 'spelling.tsv'));

// Файлы `usfm/` по именам.
List<File> _usfmFiles(Directory dir) {
  final usfm = _usfmDir(dir);
  if (!usfm.existsSync()) {
    return const [];
  }

  return usfm.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

typedef _Check = ({
  List<String> reasons,
  ({int ot, int nt, int dc}) books,
  int verses,
  Map<VerseScheme, int> schemes,
});

// Проверка записанного модуля [path]: открывается, число стихов равно
// числу `\v` в файлах, нет остатка разметки, у каждой книги есть схема.
_Check _check(String path, int expectedVerses) {
  final reasons = <String>[];
  var ot = 0;
  var nt = 0;
  var dc = 0;
  var verses = 0;
  final schemes = <VerseScheme, int>{};
  final BibleModule bible;
  try {
    bible = BibleModule.open(path);
  } on ModuleOpenException catch (e) {
    return (
      reasons: ['the module does not open: ${e.problem}'],
      books: (ot: 0, nt: 0, dc: 0),
      verses: 0,
      schemes: schemes,
    );
  }
  try {
    final places = <String>[];
    var leftovers = 0;
    void look(String where, String text) {
      if (_leftover.hasMatch(plainText(parseMarkup(text)))) {
        if (++leftovers <= _shownPlaces) {
          places.add(where);
        }
      }
    }

    for (final book in bible.books) {
      final info = BookCatalog.byNumber(book.number);
      if (info == null || info.deuterocanonical) {
        dc++;
      } else if (info.testament == Testament.old) {
        ot++;
      } else {
        nt++;
      }
      for (final chapter in book.chapters) {
        final list = bible.chapter(book.number, chapter);
        if (list.isEmpty) {
          reasons.add('${book.code} $chapter: no verses');
        }
        verses += list.length;
        for (final verse in list) {
          look('${book.code} $chapter:${verse.verse}', verse.text);
        }
        for (final heading in bible.headings(book.number, chapter)) {
          look(
            '${book.code} $chapter:${heading.verse} (heading)',
            heading.text,
          );
        }
        for (final note in bible.footnotes(book.number, chapter)) {
          look('${book.code} $chapter:${note.verse} (note)', note.text);
        }
      }
    }
    if (verses != expectedVerses) {
      reasons.add(
        '$verses verses in the module, $expectedVerses `\\v` in files',
      );
    }
    if (leftovers > 0) {
      final more = leftovers > _shownPlaces ? ', …' : '';
      reasons.add(
        'markup left in $leftovers places: ${places.join(', ')}$more',
      );
    }
    final books = bible.schemes;
    for (final number in books.uncertain) {
      reasons.add('book $number: numbering scheme is uncertain');
    }
    for (final scheme in books.schemes.values) {
      schemes[scheme] = (schemes[scheme] ?? 0) + 1;
    }
  } on Exception catch (e) {
    reasons.add('the module does not read: $e');
  } finally {
    bible.close();
  }

  return (
    reasons: reasons,
    books: (ot: ot, nt: nt, dc: dc),
    verses: verses,
    schemes: schemes,
  );
}
