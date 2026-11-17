import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('writes exact markup', () {
    expect(
      writeMarkup([
        const ParagraphBreak(),
        const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('a < b & c')]),
        const LineBreak(indent: 2),
        const TaggedWord(
          [TextRun('God')],
          strong: ['H430', 'H853'],
          morph: 'N"x',
        ),
        const FootnoteRef(3, 'a'),
      ]),
      // ignore: missing_whitespace_between_adjacent_strings
      '<p/><wj>a &lt; b &amp; c</wj><l i="2"/>'
      '<w s="H430 H853" m="N&quot;x">God</w><f id="3" c="a"/>',
    );
  });

  test('a paragraph going on is written with m and read by older readers', () {
    expect(
      writeMarkup([
        const TextRun('a'),
        const ParagraphBreak(continues: true),
        const TextRun('b'),
      ]),
      'a<p m="1"/>b',
    );
    // Читатель, который атрибута не знает, видит обычный разрыв абзаца.
    expect(parseMarkup('<p m="0"/><p x="1"/>'), [
      const ParagraphBreak(),
      const ParagraphBreak(),
    ]);
    expect(
      const ParagraphBreak(continues: true),
      isNot(const ParagraphBreak()),
    );
  });

  test('a paragraph after a blank line keeps its mark', () {
    expect(
      writeMarkup([
        const TextRun('a'),
        const ParagraphBreak(gap: true),
        const TextRun('b'),
        const ParagraphBreak(continues: true, gap: true),
        const TextRun('c'),
      ]),
      'a<p b="1"/>b<p m="1" b="1"/>c',
    );
    expect(parseMarkup('<p b="1"/><p m="1" b="1"/><p b="0"/>'), [
      const ParagraphBreak(gap: true),
      const ParagraphBreak(continues: true, gap: true),
      const ParagraphBreak(),
    ]);
    expect(const ParagraphBreak(gap: true), isNot(const ParagraphBreak()));
    expect(
      const ParagraphBreak(continues: true, gap: true).toString(),
      'ParagraphBreak(continues, gap)',
    );
  });

  test('writes plain line break and bare tagged word', () {
    expect(
      writeMarkup([
        const LineBreak(),
        const TaggedWord([TextRun('x')]),
      ]),
      '<l/><w>x</w>',
    );
  });

  test('round trips every node', () {
    final nodes = <MarkupNode>[
      const ParagraphBreak(),
      const ParagraphBreak(continues: true),
      const ParagraphBreak(gap: true),
      const ParagraphBreak(continues: true, gap: true),
      for (final style in MarkupStyle.values)
        StyledSpan(style, [TextRun('t "$style" <&>')]),
      const StyledSpan(MarkupStyle.quote, [
        TextRun('a'),
        StyledSpan(MarkupStyle.added, [TextRun('b')]),
        TaggedWord([TextRun('c')], strong: ['G1']),
      ]),
      for (var i = 0; i <= 4; i++) LineBreak(indent: i),
      const TaggedWord(
        [
          TextRun('God'),
          StyledSpan(MarkupStyle.divineName, [TextRun('x')]),
        ],
        strong: ['H430', 'H853'],
        morph: 'HNcfsa "q"',
      ),
      const TaggedWord([TextRun('only')]),
      const TextRun(' spaced  text '),
      const FootnoteRef(12, 'a'),
      const FootnoteRef(0, '"<&>'),
    ];
    expect(parseMarkup(writeMarkup(nodes)), nodes);
  });

  test('survives broken markup', () {
    expect(parseMarkup('<wj>abc'), [
      const StyledSpan(MarkupStyle.wordsOfChrist, [TextRun('abc')]),
    ]);
    expect(parseMarkup('</add>x'), [const TextRun('x')]);
    expect(parseMarkup('<zz>t</zz>'), [const TextRun('t')]);
    expect(parseMarkup('<f c="a"/>'), isEmpty);
    expect(parseMarkup('<f id="x" c="a"/>'), isEmpty);
    expect(parseMarkup('<l i="9"/>'), [const LineBreak(indent: 4)]);
    expect(parseMarkup('<l i="-3"/>'), [const LineBreak()]);
    expect(parseMarkup('a < b'), [const TextRun('a < b')]);
    expect(parseMarkup('&unknown; &amp;'), [const TextRun('&unknown; &')]);
    expect(parseMarkup(''), isEmpty);
  });

  test('nodes are equal by content', () {
    expect(const TextRun('a'), const TextRun('a'));
    expect(const LineBreak(indent: 1), isNot(const LineBreak()));
    expect(
      const TaggedWord([TextRun('a')], strong: ['H1']),
      const TaggedWord([TextRun('a')], strong: ['H1']),
    );
    expect(
      const TaggedWord([TextRun('a')], strong: ['H1']),
      isNot(const TaggedWord([TextRun('a')], strong: ['H2'])),
    );
    expect(
      const TaggedWord([TextRun('a')], morph: 'x').hashCode,
      const TaggedWord([TextRun('a')], morph: 'x').hashCode,
    );
    expect(const FootnoteRef(1, 'a'), isNot(const FootnoteRef(2, 'a')));
  });

  test('plain text skips notes and tags', () {
    expect(
      plainText(
        parseMarkup(
          '<wj>Ye <add>are</add></wj><f id="1" c="a"/><p/><w s="G1">salt</w>',
        ),
      ),
      'Ye are salt',
    );
  });

  test('plain text does not double or dangle break spaces', () {
    expect(plainText(parseMarkup('<p/>a <l/>b<l i="2"/>')), 'a b');
    expect(plainText(parseMarkup('a<l/><l/>b')), 'a b');
    expect(plainText(const []), '');
  });

  test('x tag reads and writes back', () {
    const text = 'См. <x r="MAT.1.1">Мф 1:1</x>.';
    final nodes = parseMarkup(text);
    expect(
      nodes[1],
      const CrossrefLink(RefRange(VerseRef(470, 1, 1)), [TextRun('Мф 1:1')]),
    );
    expect(writeMarkup(nodes), text);
    expect(plainText(nodes), 'См. Мф 1:1.');
  });

  test('x without a good r keeps only its text', () {
    expect(parseMarkup('<x r="bad">Мф</x>'), [const TextRun('Мф')]);
    expect(parseMarkup('<x>Мф</x>'), [const TextRun('Мф')]);
    expect(
      writeMarkup([
        const CrossrefLink(null, [TextRun('Мф')]),
      ]),
      'Мф',
    );
  });
}
