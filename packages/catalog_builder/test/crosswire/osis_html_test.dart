// Разметка OSIS и HTML режется на строки по тегам, без пробелов на стыках.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:catalog_builder/catalog_builder.dart';
import 'package:test/test.dart';

String html(String osis) => osisToHtml(osis).html;

void main() {
  group('parseOsisRef', () {
    test('a verse, a range, a chapter', () {
      expect(parseOsisRef('Gen.1.1')?.encode(), 'GEN.1.1');
      expect(parseOsisRef('Gen.1.2-Gen.1.5')?.encode(), 'GEN.1.2-GEN.1.5');
      expect(parseOsisRef('Gen.1.31-Gen.2.3')?.encode(), 'GEN.1.31-GEN.2.3');
      expect(parseOsisRef('Ps.23')?.encode(), 'PSA.23.1-PSA.23.6');
      expect(parseOsisRef('Gen.1-Gen.2')?.encode(), 'GEN.1.1-GEN.2.25');
      expect(parseOsisRef('Gen.1.3-Gen.1.3')?.encode(), 'GEN.1.3');
    });

    test('old abbreviations of Clarke', () {
      expect(parseOsisRef('Exo.34.5')?.encode(), 'EXO.34.5');
      expect(parseOsisRef('Psa.8.5')?.encode(), 'PSA.8.5');
      expect(parseOsisRef('Joh.3.16')?.encode(), 'JHN.3.16');
      expect(parseOsisRef('Jon.1.1')?.encode(), 'JON.1.1');
      expect(parseOsisRef('Phi.4.13')?.encode(), 'PHP.4.13');
      expect(parseOsisRef('Plm.1.1')?.encode(), 'PHM.1.1');
      expect(parseOsisRef('1Jn.1.1')?.encode(), '1JN.1.1');
      expect(parseOsisRef('Sol.1.1')?.encode(), 'SNG.1.1');
      for (final MapEntry(:key, :value) in crosswireBookAliases.entries) {
        expect(osisBooks[value], isNotNull, reason: key);
        expect(osisBooks.containsKey(key), isFalse, reason: key);
      }
    });

    test('what cannot be read is null', () {
      for (final bad in [
        'Ps.5.1Ch',
        'Xyz.1.1',
        'Gen.50.27',
        'Gen.51.1',
        'Gen.1.0',
        'Job.6.1-Job.4.1',
        'Gen.50.1-Exod.1.1',
        'Gen.1.1-Gen.1.2-Gen.1.3',
        'Gen',
        '',
      ]) {
        expect(parseOsisRef(bad), isNull, reason: bad);
      }
    });
  });

  group('osisToHtml', () {
    test('x-p milestones are paragraphs; empty ones are dropped', () {
      expect(
        html(
          '<div eID="a" type="x-p"/> <div sID="b" type="x-p"/> One  two. '
          '<div eID="b" type="x-p"/> <div sID="c" type="x-p"/>\n'
          '<div eID="c" type="x-p"/><div sID="d" type="x-p"/>Three.',
        ),
        '<p>One two.</p><p>Three.</p>',
      );
      expect(html('<div sID="a" type="x-p"/> <div eID="a" type="x-p"/>'), '');
      expect(html(''), '');
      expect(html('﻿'), '');
    });

    test('titles are headings by type', () {
      expect(
        html(
          '<title type="x-ms">A</title><title type="x-s">B</title>'
          '<title type="x-s2">C</title><title type="x-s3">D</title>'
          '<title>E</title><title type="x-s"> </title>Text',
        ),
        '<h3>A</h3><h4>B</h4><h5>C</h5><h6>D</h6><h4>E</h4><p>Text</p>',
      );
    });

    test('hi bold and italic; other hi is text', () {
      expect(
        html(
          '<hi type="bold">Verse 1</hi> <hi type="italic">and</hi> '
          '<hi type="underline">u</hi>',
        ),
        '<p><b>Verse 1</b> <i>and</i> u</p>',
      );
    });

    test('references become ref: links or stay text', () {
      final out = osisToHtml(
        'See <reference osisRef="Gen.1.1">Gen 1:1</reference>, '
        '<reference osisRef="Exo.12.1-Exo.12.3">Exo 12:1-3</reference>, '
        '<reference osisRef="Ps.23">Ps 23</reference> and '
        '<reference osisRef="Job.6.1-Job.4.1">Job 6:1-4</reference>.',
      );
      expect(
        out.html,
        '<p>See <a href="ref:GEN.1.1">Gen 1:1</a>, '
        '<a href="ref:EXO.12.1-EXO.12.3">Exo 12:1-3</a>, '
        '<a href="ref:PSA.23.1-PSA.23.6">Ps 23</a> and Job 6:1-4.</p>',
      );
      expect(out.links, 3);
      expect(out.unresolved, 1);
    });

    test('notes: numbers in the text, notes at the end', () {
      final out = osisToHtml(
        '<title type="x-ms">Ruth<note placement="foot">On the '
        '<hi type="italic">title</hi>.</note></title>'
        '<div sID="a" type="x-p"/>Text<note placement="foot">See '
        '<reference osisRef="Gen.1.1">Gen 1:1</reference>.</note> more.'
        '<div eID="a" type="x-p"/>',
      );
      expect(
        out.html,
        '<h3>Ruth<sup>1</sup></h3><p>Text<sup>2</sup> more.</p>'
        '<p><sup>1</sup> On the <i>title</i>.</p>'
        '<p><sup>2</sup> See <a href="ref:GEN.1.1">Gen 1:1</a>.</p>',
      );
      expect(out.notes, 2);
      expect(out.links, 1);
    });

    test('tables and lists', () {
      expect(
        html(
          'Before <table> <row><cell role="label">A</cell><cell>B '
          '<hi type="italic">b</hi></cell></row> <row><cell></cell>'
          '<cell>1</cell></row> </table> after <list> '
          '<item type="x-indent-1">one</item> <item>two</item> </list>',
        ),
        '<p>Before</p><table><tr><td>A</td><td>B <i>b</i></td></tr>'
        '<tr><td></td><td>1</td></tr></table><p>after</p>'
        '<ul><li>one</li><li>two</li></ul>',
      );
    });

    test('poetry lines are joined with <br>', () {
      expect(
        html(
          'Ps 18 <div eID="a" type="x-p"/> <lg sID="b"/> '
          '<l level="1" sID="c"/>Line one,<l eID="c" level="1"/> '
          '<l level="1" sID="d"/>line two.<l eID="d" level="1"/> '
          '<lg eID="b"/> After.',
        ),
        '<p>Ps 18</p><p>Line one,<br>line two.</p><p>After.</p>',
      );
    });

    test('milestones and unknown tags: dropped, text kept', () {
      expect(
        html(
          '<div canonical="true" osisID="Gen" sID="g" type="book"/>'
          '<milestone n="" type="x-usfm-toc1"/>'
          '<chapter n="1" osisID="Gen.1" sID="Gen.1"/>'
          '<div sID="i" type="introduction"/>'
          '<div type="x-milestone" subType="x-preverse" sID="pv1"/>'
          '<foreign xml:lang="he">שלום</foreign> '
          '<chapter eID="Gen.1"/>',
        ),
        '<p>שלום</p>',
      );
    });

    test('an inline tag across a paragraph break is reopened', () {
      expect(
        html(
          '<hi type="italic">one <div eID="a" type="x-p"/> '
          '<div sID="b" type="x-p"/> two</hi> three',
        ),
        '<p><i>one</i></p><p><i>two</i> three</p>',
      );
    });

    test('entities stay; stray & and < are escaped', () {
      expect(
        html('A &amp; B &lt;c&gt; D & E < F'),
        '<p>A &amp; B &lt;c&gt; D &amp; E &lt; F</p>',
      );
    });

    test('unclosed tags are closed at the end', () {
      expect(
        html('<hi type="bold">open <note>n'),
        '<p><b>open <sup>1</sup></b></p><p><sup>1</sup> n</p>',
      );
    });
  });
}
