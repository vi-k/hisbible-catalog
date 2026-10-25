import 'dart:io';

import 'package:hisbible_format/hisbible_format.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _commentaries = ModuleMeta(
  type: ModuleType.commentaries,
  abbreviation: 'Com',
  name: 'Commentary',
  language: 'ru',
  direction: WritingDirection.ltr,
  numbering: 'rso',
);

const _crossrefs = ModuleMeta(
  type: ModuleType.crossReferences,
  abbreviation: 'OB',
  name: 'Open Bible',
  language: 'en',
  direction: WritingDirection.ltr,
  numbering: 'eng',
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hisbible_format_comments_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('writes and reads comments', () {
    final path = '${dir.path}/Com.commentaries.hb';
    ModuleWriter.create(path, _commentaries)
      ..addComment(500, 3, 1, '<p>Никодим</p>')
      ..addComment(500, 3, 16, '<p>Так возлюбил</p>', verseEnd: 18)
      ..addComment(500, 3, 2, 'Ночью')
      ..addComment(500, 4, 1, 'Глава 4', chapterEnd: 5, verseEnd: 3)
      ..finish();

    expect(checkModuleFile(path), isNull);
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(db.close);
    expect(
      db.select('SELECT DISTINCT book FROM comments').single.columnAt(0),
      'JHN',
    );
    final module = CommentaryModule.open(path);
    addTearDown(module.close);
    expect(module.meta, _commentaries);
    final chapter = module.comments(500, 3);
    expect(chapter, hasLength(3));
    expect([for (final c in chapter) c.verse], [1, 2, 16]);
    expect(chapter[0].html, '<p>Никодим</p>');
    expect(chapter[0].book, 500);
    expect(chapter[0].chapter, 3);
    expect(chapter[0].verseEnd, isNull);
    expect(chapter[0].chapterEnd, isNull);
    expect(chapter[2].verseEnd, 18);
    final fourth = module.comments(500, 4).single;
    expect((fourth.chapterEnd, fourth.verseEnd), (5, 3));
    expect(module.comments(500, 5), isEmpty);
    expect(module.comments(10, 1), isEmpty);
    expect(module.comments(9999, 1), isEmpty);
  });

  test('writes and reads cross references', () {
    final path = '${dir.path}/OB.crossreferences.hb';
    const low = CrossRef(
      book: 500,
      chapter: 3,
      verse: 16,
      toBook: 520,
      toChapter: 5,
      toVerse: 8,
      votes: 12,
    );
    const high = CrossRef(
      book: 500,
      chapter: 3,
      verse: 16,
      verseEnd: 17,
      toBook: 10,
      toChapter: 1,
      toVerse: 1,
      toChapterEnd: 2,
      toVerseEnd: 3,
      votes: 40,
    );
    const other = CrossRef(
      book: 500,
      chapter: 3,
      verse: 1,
      toBook: 520,
      toChapter: 1,
      toVerse: 1,
    );
    ModuleWriter.create(path, _crossrefs)
      ..addCrossref(low)
      ..addCrossref(high)
      ..addCrossref(other)
      ..finish();

    expect(checkModuleFile(path), isNull);
    final module = CrossrefModule.open(path);
    addTearDown(module.close);
    expect(module.meta, _crossrefs);
    expect(module.from(500, 3), [other, high, low]);
    expect(module.from(500, 4), isEmpty);
    expect(module.from(520, 5), isEmpty);
    expect(other.votes, 0);
  });

  test('empty commentary is rejected', () {
    final comments = '${dir.path}/empty.commentaries.hb';
    ModuleWriter.create(comments, _commentaries).finish();
    expect(checkModuleFile(comments), const EmptyModule());
    expect(
      () => CommentaryModule.open(comments),
      throwsA(
        isA<ModuleOpenException>().having(
          (e) => e.problem,
          'problem',
          const EmptyModule(),
        ),
      ),
    );

    final refs = '${dir.path}/empty.crossreferences.hb';
    ModuleWriter.create(refs, _crossrefs).finish();
    expect(checkModuleFile(refs), const EmptyModule());
    expect(
      () => CrossrefModule.open(refs),
      throwsA(isA<ModuleOpenException>()),
    );
  });

  test('module of another type is unsupported', () {
    final path = '${dir.path}/Com.commentaries.hb';
    ModuleWriter.create(path, _commentaries)
      ..addComment(500, 3, 1, 'x')
      ..finish();
    expect(
      () => CrossrefModule.open(path),
      throwsA(
        isA<ModuleOpenException>().having(
          (e) => e.problem,
          'problem',
          const UnsupportedType('commentaries'),
        ),
      ),
    );
    expect(() => BibleModule.open(path), throwsA(isA<ModuleOpenException>()));
  });

  test('writer rejects records of another type', () {
    final path = '${dir.path}/Com.commentaries.hb';
    final writer = ModuleWriter.create(path, _commentaries);
    addTearDown(writer.abort);
    expect(
      () => writer.addCrossref(
        const CrossRef(
          book: 500,
          chapter: 1,
          verse: 1,
          toBook: 10,
          toChapter: 1,
          toVerse: 1,
        ),
      ),
      throwsStateError,
    );
    expect(() => writer.addVerse(500, 1, 1, 'x'), throwsStateError);
  });
}
