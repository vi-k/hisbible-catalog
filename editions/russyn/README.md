# Russian Synodal Bible (RST), complete edition

The Synodal translation of 1876 in its complete form: 77 books, including the
deuterocanonical ones. The module id is `russyn`, the abbreviation is `RST`.

## Source and licence

The text is based on the RusSynodal 1.9.1 module of the CrossWire library
(Public Domain). It was checked against the edition of the Moscow Patriarchate,
and the cross-references come from that edition. The spelling is modern.

## What is in the text

- Square brackets mark passages that the Synodal translation adds from the
  Septuagint.
- Italics mark words the translators added for the sense.
- Stress marks are kept where the edition has them.
- Footnotes are the notes of the edition.
- Cross-references are the parallel passages of the edition.
- The Prayer of Manasseh stands in 2 Chronicles 36:24-35, as in the edition of
  the Moscow Patriarchate, under its own heading with a footnote.
- The prologue of Sirach is the introduction of the book, not a heading of 1:1.
- The full book titles are those of the edition of the Moscow Patriarchate.

None of these is listed in `CHANGES.md`, because they are part of the edition
and not changes to the base text.

## Changes to the base text

Every change to the words of the base text has a row in `CHANGES.md`: the
place, the base reading, the accepted reading and the reason.

`spelling.tsv` is the table of old and new spellings: old word, tab, new word.
The builder applies it to the text, carrying the capital letter over.

## Files

- `edition.json`: module description.
- `usfm/`: one USFM file per book.
- `CHANGES.md`: log of changes to the base text.
- `spelling.tsv`: spelling table.

Build:
`dart run catalog_builder:build --edition editions/russyn out/russyn.hb`.
