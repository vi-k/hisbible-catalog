/// Фикстуры для тестов: модули Библии формата HisBible во временных файлах.
///
/// Подключается тестами этого пакета и тестами приложения; в рабочий код
/// не входит.
library;

import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';

/// Книга для [writeBibleFixture].
final class FixtureBook {
  /// Создаёт книгу; [longName] по умолчанию равен [shortName].
  const FixtureBook(this.number, this.shortName, {this.longName, this.color});

  /// Номер книги справочника.
  final int number;

  /// Короткое название.
  final String shortName;

  /// Полное название; `null` — как короткое.
  final String? longName;

  /// Цвет `0xRRGGBB`; `null` — цвет справочника.
  final int? color;
}

/// Описание модуля, которое [writeBibleFixture] берёт по умолчанию.
const ModuleMeta fixtureMeta = ModuleMeta(
  type: ModuleType.bible,
  abbreviation: 'Test',
  name: 'Test',
  language: 'ru',
  direction: WritingDirection.ltr,
);

/// Пишет в [path] модуль Библии через [ModuleWriter].
///
/// Стихи `(книга, глава, стих)` и их тексты в разметке формата идут
/// в порядке карты, заголовки — `(книга, глава, стих, порядок, текст)`:
/// вид [HeadingKind.section], уровень 1, над одним стихом — по порядку.
/// Схема книги берётся из [schemes], а без неё распознаётся по последним
/// стихам глав, как у модулей без схемы; книга без кода SIL —
/// [VerseScheme.eng]. Существующий файл заменяется, папки создаются.
void writeBibleFixture(
  String path, {
  ModuleMeta? meta,
  required List<FixtureBook> books,
  required Map<(int, int, int), String> verses,
  List<(int, int, int, int, String)> headings = const [],
  Map<int, VerseScheme> schemes = const {},
}) {
  final moduleMeta = meta ?? fixtureMeta;
  final lastVerses = <int, Map<int, int>>{};
  for (final (book, chapter, verse) in verses.keys) {
    final last = lastVerses.putIfAbsent(book, () => {});
    if (verse > (last[chapter] ?? 0)) {
      last[chapter] = verse;
    }
  }
  final detected = Versification.standard.detect(
    lastVerses,
    russianFlag: moduleMeta.language.toLowerCase().startsWith('ru'),
  );
  File(path).parent.createSync(recursive: true);
  final writer = ModuleWriter.create(path, moduleMeta);
  try {
    for (final book in books) {
      writer.addBook(
        number: book.number,
        shortName: book.shortName,
        longName: book.longName ?? book.shortName,
        scheme: schemes[book.number] ?? detected.of(book.number),
        color: book.color,
      );
    }
    for (final MapEntry(key: (book, chapter, verse), :value)
        in verses.entries) {
      writer.addVerse(book, chapter, verse, value);
    }
    // List.sort нестабилен, а равные заголовки идут в порядке списка.
    final indexed = [for (var i = 0; i < headings.length; i++) (i, headings[i])]
      ..sort((a, b) {
        final byOrder = a.$2.$4.compareTo(b.$2.$4);

        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    for (final (_, (book, chapter, verse, _, text)) in indexed) {
      writer.addHeading(book, chapter, verse, HeadingKind.section, 1, text);
    }
    writer.finish();
  } on Object {
    writer.abort();
    rethrow;
  }
}
