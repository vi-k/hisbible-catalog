// Разметка OSIS и HTML режется на строки по тегам, без пробелов на стыках.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:catalog_builder/catalog_builder.dart';
import 'package:test/test.dart';

ZComRecord rec(int chapter, int verse, String text, {int? verseEnd}) =>
    ZComRecord(
      book: 10,
      chapter: chapter,
      verse: verse,
      verseEnd: verseEnd,
      text: text,
    );

typedef Row = (CommentPartKind, int, int, int?, String);

List<Row> rows(SplitArticles split) => [
  for (final p in split.parts)
    (p.kind, p.chapter, p.verse, p.verseEnd, osisToHtml(p.osis).html),
];

const comment = CommentPartKind.comment;
const bookArticle = CommentPartKind.bookArticle;
const chapterArticle = CommentPartKind.chapterArticle;

void main() {
  group('Clarke: verse label', () {
    test('chapter 1: the book article, then verse 1', () {
      final split = splitArticles([
        rec(
          1,
          1,
          '<div eID="a" type="x-p"/> <title type="x-s">Preface</title> '
          '<div sID="b" type="x-p"/> Every believer. <div eID="b" type="x-p"/>'
          ' <div sID="c" type="x-p"/> <hi type="bold">Verse 1</hi> '
          '<div eID="c" type="x-p"/> <div sID="d" type="x-p"/> God in the '
          'beginning.',
        ),
        rec(1, 2, '<hi type="bold">Verse 2</hi> The earth.'),
      ], ArticleMarker.verseLabel);

      expect(rows(split), [
        (bookArticle, 0, 0, null, '<h4>Preface</h4><p>Every believer.</p>'),
        (
          comment,
          1,
          1,
          null,
          '<p><b>Verse 1</b></p><p>God in the beginning.</p>',
        ),
        (comment, 1, 2, null, '<p><b>Verse 2</b> The earth.</p>'),
      ]);
      expect((split.split, split.whole, split.shifted), (1, 0, 0));
    });

    test('other chapters: the chapter article; Verse 10 is not Verse 1', () {
      final split = splitArticles([
        rec(
          2,
          1,
          '<title type="x-s">Introduction</title> The seventh day. '
          '<hi type="bold">Verse 1</hi> Thus the heavens.',
        ),
        rec(3, 1, '<title type="x-s">Introduction</title> Satan. '),
        rec(4, 10, '<hi type="bold">Verse 10</hi> Ten.'),
      ], ArticleMarker.verseLabel);

      expect(rows(split), [
        (
          chapterArticle,
          2,
          0,
          null,
          '<h4>Introduction</h4><p>The seventh day.</p>',
        ),
        (comment, 2, 1, null, '<p><b>Verse 1</b> Thus the heavens.</p>'),
        // Нет метки — вся запись введение.
        (chapterArticle, 3, 0, null, '<h4>Introduction</h4><p>Satan.</p>'),
        (comment, 4, 10, null, '<p><b>Verse 10</b> Ten.</p>'),
      ]);
      expect((split.split, split.whole), (1, 1));
    });

    test('verse 1 without a title stays a comment', () {
      final split = splitArticles([
        rec(5, 1, 'Text <hi type="bold">Verse 1</hi> more'),
      ], ArticleMarker.verseLabel);

      expect(rows(split).single.$1, comment);
      expect(split.split, 0);
    });
  });

  group('KD: reference to verse 1', () {
    test('a paragraph opened by a reference tag', () {
      final split = splitArticles([
        rec(
          1,
          1,
          '<title type="x-ms">GENERAL INTRODUCTION</title> Intro, see '
          '<reference osisRef="Gen.1.1">Gen 1:1</reference>. '
          '<div eID="a" type="x-p"/> <div sID="b" type="x-p"/> '
          '<reference osisRef="Gen.1.1">Gen 1:1</reference> '
          '<div eID="b" type="x-p"/> <div sID="c" type="x-p"/> In the '
          'beginning.',
        ),
        rec(
          1,
          2,
          '<reference osisRef="Gen.1.2-Gen.1.5">Gen 1:2-5</reference> Day.',
          verseEnd: 5,
        ),
      ], ArticleMarker.verseReference);

      expect(rows(split), [
        (
          bookArticle,
          0,
          0,
          null,
          '<h3>GENERAL INTRODUCTION</h3><p>Intro, see '
              '<a href="ref:GEN.1.1">Gen 1:1</a>.</p>',
        ),
        (
          comment,
          1,
          1,
          null,
          '<p><a href="ref:GEN.1.1">Gen 1:1</a></p><p>In the beginning.</p>',
        ),
        (
          comment,
          1,
          2,
          5,
          '<p><a href="ref:GEN.1.2-GEN.1.5">Gen 1:2-5</a> Day.</p>',
        ),
      ]);
      expect(split.split, 1);
    });

    test('a paragraph opened by a reference in plain text', () {
      final split = splitArticles([
        rec(
          3,
          1,
          '<title type="x-s">Introduction</title> <div sID="a" type="x-p"/>'
          'Text. <div eID="a" type="x-p"/> <div sID="b" type="x-p"/> '
          'Gen 3:1-3 <div eID="b" type="x-p"/> Comment.',
          verseEnd: 3,
        ),
      ], ArticleMarker.verseReference);

      expect(rows(split), [
        (chapterArticle, 3, 0, null, '<h4>Introduction</h4><p>Text.</p>'),
        (comment, 3, 1, 3, '<p>Gen 3:1-3</p><p>Comment.</p>'),
      ]);
    });

    test(
      'a reference inside the text or to another chapter does not split',
      () {
        final split = splitArticles([
          rec(
            3,
            1,
            '<title type="x-s">The Fall</title> <div sID="a" type="x-p"/>The '
            'serpent (<reference osisRef="Gen.3.1">Gen 3:1</reference>). '
            '<div eID="a" type="x-p"/> <div sID="b" type="x-p"/> '
            '<reference osisRef="Gen.2.1">Gen 2:1</reference> more',
          ),
        ], ArticleMarker.verseReference);

        expect(rows(split).single.$1, comment);
        expect(split.split, 0);
      },
    );

    test('introduction alone at verse 1: the comment moves to verse 1', () {
      final split = splitArticles([
        rec(2, 1, '<title type="x-s2">Psalm 2</title> About the psalm.'),
        rec(
          2,
          2,
          '<reference osisRef="Gen.2.1-Gen.2.3">Gen 2:1-3</reference> Why.',
          verseEnd: 3,
        ),
        rec(2, 4, '<reference osisRef="Gen.2.4">Gen 2:4</reference> He.'),
      ], ArticleMarker.verseReference);

      expect(rows(split).map((r) => (r.$1, r.$2, r.$3, r.$4)), [
        (chapterArticle, 2, 0, null),
        (comment, 2, 1, 3),
        (comment, 2, 4, null),
      ]);
      expect((split.split, split.whole, split.shifted), (0, 1, 1));
    });

    test('no marker and no shifted comment: verse 1 stays a comment', () {
      final split = splitArticles([
        rec(
          21,
          1,
          '<title type="x-s">BIRTH OF ISAAC</title> Vers. 1-7. Birth.',
          verseEnd: 7,
        ),
        rec(21, 8, 'Vers. 8-21. Expulsion.', verseEnd: 21),
        rec(22, 1, '<title type="x-s">Trial</title> Intro.'),
        rec(22, 2, '<reference osisRef="Gen.22.2">Gen 22:2</reference> x'),
      ], ArticleMarker.verseReference);

      expect(rows(split).map((r) => (r.$1, r.$2, r.$3, r.$4)), [
        (comment, 21, 1, 7),
        (comment, 21, 8, 21),
        (comment, 22, 1, null),
        (comment, 22, 2, null),
      ]);
    });
  });

  group('KD: the leading reference', () {
    final psa = parseOsisRef('Ps.1.1')!.start.book;
    ZComRecord psRec(int chapter, int verse, String text, {int? verseEnd}) =>
        ZComRecord(
          book: psa,
          chapter: chapter,
          verse: verse,
          verseEnd: verseEnd,
          text: text,
        );
    List<(CommentPartKind, int, int, int?)> places(SplitArticles split) => [
      for (final p in split.parts) (p.kind, p.chapter, p.verse, p.verseEnd),
    ];

    test('the comment takes the range of its leading reference', () {
      final split = splitArticles([
        psRec(
          5,
          3,
          '<reference osisRef="Ps.5.2-Ps.5.4">Psa 5:2-4</reference>'
          '<div type="x-p" sID="a"/> Comment.',
        ),
      ], ArticleMarker.verseReference);

      expect(places(split), [(comment, 5, 2, 4)]);
      expect(split.widened, 1);
    });

    test('Psalm 23: verse 1 with a title becomes the chapter article', () {
      final split = splitArticles([
        psRec(23, 1, '<title type="x-s2">The Good Shepherd</title> Intro.'),
        psRec(
          23,
          3,
          '<reference osisRef="Ps.23.1-Ps.23.3">Psa 23:1-3</reference>'
          '<div type="x-p" sID="a"/> The poet.',
        ),
        psRec(
          23,
          4,
          '<reference osisRef="Ps.23.4-Ps.23.5">Psa 23:4-5</reference>'
          '<div type="x-p" sID="b"/> Rod and staff.',
          verseEnd: 5,
        ),
      ], ArticleMarker.verseReference);

      expect(places(split), [
        (chapterArticle, 23, 0, null),
        (comment, 23, 1, 3),
        (comment, 23, 4, 5),
      ]);
      expect((split.widened, split.whole), (1, 1));
    });

    test('in chapter 1 verse 1 with a title becomes the book article', () {
      final split = splitArticles([
        psRec(1, 1, '<title type="x-s2">The Psalter</title> Intro.'),
        psRec(
          1,
          2,
          '<reference osisRef="Ps.1.1-Ps.1.3">Psa 1:1-3</reference>',
          verseEnd: 3,
        ),
      ], ArticleMarker.verseReference);

      expect(places(split), [(bookArticle, 0, 0, null), (comment, 1, 1, 3)]);
    });

    test('verse 1 without a title stays a comment', () {
      final split = splitArticles([
        psRec(7, 1, 'No title here.'),
        psRec(7, 2, '<reference osisRef="Ps.7.1-Ps.7.2">Psa 7:1-2</reference>'),
      ], ArticleMarker.verseReference);

      expect(places(split), [(comment, 7, 1, null), (comment, 7, 1, 2)]);
      expect((split.widened, split.whole), (1, 0));
    });

    test('a reference elsewhere or not covering the place is left alone', () {
      final split = splitArticles([
        // В другую главу.
        psRec(
          4,
          1,
          '<reference osisRef="Ps.1.1-Ps.1.9">Psa 1:1-9</reference> Moses.',
        ),
        // Уже места записи.
        psRec(
          35,
          21,
          '<reference osisRef="Ps.35.21-Ps.35.22">Psa 35:21-22</reference>',
          verseEnd: 29,
        ),
        // Не одна в первом абзаце.
        psRec(
          36,
          3,
          '<reference osisRef="Ps.36.2-Ps.36.4">Psa 36:2-4</reference> and '
          '<reference osisRef="Ps.36.5">Psa 36:5</reference>.',
        ),
        // Через главы.
        psRec(
          37,
          3,
          '<reference osisRef="Ps.37.1-Ps.38.2">Psa 37:1-38:2</reference>',
        ),
      ], ArticleMarker.verseReference);

      expect(places(split), [
        (comment, 4, 1, null),
        (comment, 35, 21, 29),
        (comment, 36, 3, null),
        (comment, 37, 3, null),
      ]);
      expect(split.widened, 0);
    });

    test('Clarke keeps the places of its records', () {
      final split = splitArticles([
        psRec(5, 3, '<reference osisRef="Ps.5.2-Ps.5.4">Psa 5:2-4</reference>'),
      ], ArticleMarker.verseLabel);

      expect(places(split), [(comment, 5, 3, null)]);
      expect(split.widened, 0);
    });
  });

  test('book and chapter records are articles', () {
    final split = splitArticles([
      rec(0, 0, '<div type="book"/> About the book'),
      rec(17, 0, 'v 1 Want of Water'),
      rec(17, 1, 'Comment'),
    ], ArticleMarker.verseReference);

    expect(rows(split).map((r) => (r.$1, r.$2, r.$3)), [
      (bookArticle, 0, 0),
      (chapterArticle, 17, 0),
      (comment, 17, 1),
    ]);
  });

  test('a split before nothing but milestones does not split', () {
    final split = splitArticles([
      rec(
        2,
        1,
        '<title type="x-s"> </title><div sID="a" type="x-p"/> '
        '<hi type="bold">Verse 1</hi> Text',
      ),
    ], ArticleMarker.verseLabel);

    // Перед меткой пусто: не статья. Метка есть — запись остаётся
    // толкованием, а не статьёй целиком.
    expect(rows(split).single.$1, comment);
    expect(split.split, 0);
  });
}
