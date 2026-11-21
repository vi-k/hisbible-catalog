# Russian Synodal Bible (RST), complete edition

The Synodal translation of 1876 in its complete form: 77 books, including the
deuterocanonical ones. The module id is `russyn`, the abbreviation is `RST`.

## Source and licence

The text is based on the RusSynodal 1.9.1 module of the CrossWire library
(Public Domain). It was checked against the edition of the Moscow Patriarchate,
and the cross-references come from that edition. It was then read against the
printed Bible of the Moscow Patriarchate, and where the printed book differs,
the edition follows the book. The spelling is modern.

## What is in the text

- Square brackets mark passages that the Synodal translation adds from the
  Septuagint.
- Italics mark words the translators added for the sense.
- Dashes and quotation marks are set as in the printed book: a long dash
  with spaces (` — `) and guillemets (`«»`).
- Stress marks are kept where the edition has them.
- Footnotes are the notes of the edition.
- Cross-references are the parallel passages of the edition. A verse lists
  them in the order of the books, and by chapter and verse within a book, as
  the printed Synodal Bible does; a book is named only before its first
  passage, and a verse of the same chapter follows after a comma without the
  chapter (`Gen 37:5, 9`).
- The Prayer of Manasseh stands in 2 Chronicles 36:24-35, as in the edition of
  the Moscow Patriarchate, under its own heading with a footnote. As in the
  printed edition, its verses show no numbers: verses 24-34 end with a letter
  in italics and square brackets, *[а]* to *[л]*, and verse 35 has none (the
  `\zvl` marker after the verse number). References keep the numbers 24-35.
- The prologue of Sirach is the introduction of the book, not a heading of 1:1.
- The full book titles are those of the printed book (`От Матфея святое
  благовествование`, `Книга пророка Исаии`); books whose title the printed
  book does not change keep the title of the online edition of the Moscow
  Patriarchate.

None of these is listed in `CHANGES.md`, because they are part of the edition
and not changes to the base text. Readings of `CHANGES.md` are set with the
same dashes and quotation marks as the text.

## Changes to the base text

Every change to the words, punctuation or capitals of the base text has
a row in `CHANGES.md`: the place, the base reading, the accepted reading and
the reason. Typesetting errors of the base (a space before a punctuation
mark, a dash instead of a hyphen inside a word) are corrected; the
punctuation of a verse and the capitals of pronouns follow the edition of
the Moscow Patriarchate where it is confirmed by a second witness. Readings
of the printed book are marked `по печатной книге`; footnotes the printed
book adds or words differently are not listed, like other footnotes.

`spelling.tsv` is the table of old and new spellings: old word, tab, new word.
The builder applies it to the text, carrying the capital letter over.

## Files

- `edition.json`: module description.
- `usfm/`: one USFM file per book.
- `CHANGES.md`: log of changes to the base text.
- `spelling.tsv`: spelling table.

Build:
`dart run catalog_builder:build --edition editions/russyn out/russyn.hb`.
