# HisBible module format

A HisBible module is one SQLite database file with the extension `.hb`. One
file holds one module: a Bible translation, commentaries, or cross references.
This document describes version 2 of the file format, the verse markup, links
in commentaries, and the catalog index. The Dart package
`packages/hisbible_format` reads and writes these files (`ModuleWriter`,
`BibleModule`, `checkModuleFile`).

File names follow the module type: `<abbreviation>.hb` for a Bible,
`<abbreviation>.commentaries.hb` and `<abbreviation>.crossreferences.hb` for
the other types.

## File format

### Signature and version

- `PRAGMA application_id = 1214857833` (`0x48694269`, the bytes `HiBi`). A file
  is a HisBible module when its `application_id` is 1214857833 and its
  `user_version` is at least 1; any other SQLite database is not a module.
- `PRAGMA user_version` is the format version, currently `2`. A reader that
  knows version `N` opens files of versions `1..N` and rejects newer ones.
- Adding an optional `meta` key, a table, or a column does not change the
  version: readers skip what they do not know. The version grows only with an
  incompatible change.
- A module contains only tables and their indexes: no views, triggers or
  virtual tables. A reader refuses a file with any other schema object.

### Schema of version 2

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE books (
  position INTEGER PRIMARY KEY,  -- order of books in the module, from 1
  code TEXT NOT NULL UNIQUE,     -- USFM code or H<number>
  short_name TEXT NOT NULL,      -- "Gen", "Быт"
  long_name TEXT NOT NULL,       -- "Genesis", "Бытие"
  title TEXT,                    -- full title (\toc1)
  scheme TEXT NOT NULL,          -- eng | org | rso | rsc | lxx | vul
  color INTEGER                  -- deprecated: writers leave NULL, readers ignore it
);
CREATE TABLE verses (            -- one row per piece of a chapter
  book TEXT NOT NULL, chapter INTEGER NOT NULL,
  position INTEGER NOT NULL,     -- place of the piece in the chapter, from 0
  verse INTEGER NOT NULL, part TEXT NOT NULL,  -- start; part: '' or a letter
  verse_end INTEGER, part_end TEXT NOT NULL,   -- end; NULL: one verse
  text TEXT NOT NULL,            -- markup, see "Markup"
  PRIMARY KEY (book, chapter, position),
  UNIQUE (book, chapter, verse, part)
) WITHOUT ROWID;
CREATE TABLE headings (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,            -- the piece (verse, part) it stands above
  position INTEGER NOT NULL,     -- order above one piece, from 0
  kind TEXT NOT NULL,            -- major | section | title | parallel
  level INTEGER NOT NULL,        -- 1..3
  text TEXT NOT NULL,            -- markup without <p/> and <l/>
  PRIMARY KEY (book, chapter, verse, part, position)
) WITHOUT ROWID;
CREATE TABLE intros (            -- optional, bible only
  book TEXT NOT NULL,            -- book code, or FRT for the preface
  position INTEGER NOT NULL,     -- order in the book, from 0
  kind TEXT NOT NULL,            -- title | paragraph | item | article | author
                                 -- | bookTitle | bookSubtitle
  text TEXT NOT NULL,            -- markup
  PRIMARY KEY (book, position)
) WITHOUT ROWID;
CREATE TABLE verse_labels (      -- optional, bible only
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,            -- the piece (verse, part)
  label TEXT NOT NULL,           -- shown at the end of the piece; '' for none
  PRIMARY KEY (book, chapter, verse, part)
) WITHOUT ROWID;
CREATE TABLE verse_numbers (     -- optional, bible only
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  part TEXT NOT NULL,            -- the piece (verse, part)
  number TEXT NOT NULL,          -- shown instead of the verse number
  PRIMARY KEY (book, chapter, verse, part)
) WITHOUT ROWID;
CREATE TABLE footnotes (
  id INTEGER PRIMARY KEY,        -- what <f id> refers to
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  kind TEXT NOT NULL,            -- note | crossref
  caller TEXT NOT NULL,          -- footnote mark; '' for none
  text TEXT NOT NULL             -- markup
);
CREATE INDEX footnotes_place ON footnotes (book, chapter, verse);
CREATE TABLE comments (          -- commentaries only
  id INTEGER PRIMARY KEY,
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  chapter_end INTEGER, verse_end INTEGER,
  text TEXT NOT NULL             -- HTML, see "Links in commentaries"
);
CREATE INDEX comments_place ON comments (book, chapter, verse);
CREATE TABLE crossrefs (         -- cross references only
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  verse_end INTEGER,
  to_book TEXT NOT NULL, to_chapter INTEGER NOT NULL, to_verse INTEGER NOT NULL,
  to_chapter_end INTEGER, to_verse_end INTEGER,
  votes INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX crossrefs_place ON crossrefs (book, chapter, verse);
```

Tables by module type:

| type | tables |
|---|---|
| `bible` | `meta`, `books`, `verses`, `headings`, `footnotes`; optionally `intros`, `verse_labels`, `verse_numbers` |
| `commentaries` | `meta`, `comments` |
| `crossreferences` | `meta`, `crossrefs` |

Notes:

- `book` columns hold book codes: the USFM code (`GEN`, `PSA`, `MAT`) or
  `H<number>` for a book that has no USFM code; the number is a book number of
  the HisBible book list (`BookCatalog` in `hisbible_format`). Additions to
  Esther (192) are `ESG` since `hisbible_format` 0.17.2; a reader still takes
  their former code `H192`. `ESG` is either the whole Greek Esther (WEB) or
  only the additions, chapters 10–16 (KJV, RV); no scheme maps it, and its
  places map to themselves.
- A reader skips verses of a book that is not in `books`, and books whose code
  it does not know. A Bible has at least one verse of a book from `books`.
- `scheme` is the verse numbering of the book, named as the SIL versification
  files: `eng` (English), `org` (original: a psalm title is verse 1), `rso`
  (Russian Synodal, full edition), `rsc` (Russian Synodal, canonical edition),
  `lxx` (Septuagint: Greek psalm numbering, deuterocanonical books as `org`),
  `vul` (Vulgate). A reader that does not know a scheme reads the book as
  `eng`. The SIL files `eng` and `rso` do not map the deuterocanonical books;
  for them `eng` (numbered as the KJV and Brenton number them) and `rso` map to
  `org` (the Greek text as Rahlfs numbers it) by the tables of
  `hisbible_format` (`eng_deutero_vrs.dart`, `rso_deutero_vrs.dart`).
- In a Bible whose 2 Chronicles follows `rsc` or `rso`, or, in a Bible without
  a book `MAN`, whose 2 Chronicles 36 has more than 23 verses, 2 Chronicles
  36:24–35 is the Prayer of Manasseh; in `rso`, so is 2 Chronicles 37. A reader
  finds where a Bible keeps the prayer from its books and chapters: with a book
  `MAN`, the prayer is that book; otherwise, with more than 23 verses in 2
  Chronicles 36, it follows verse 23 there; otherwise, with a chapter 37 of 2
  Chronicles, it is that chapter; otherwise the Bible has no prayer.
  Commentaries and cross references find it the same way from the places of
  their records. Places of the prayer map to and from `MAN` by the
  `2CH 37 = MAN` lines of the SIL file `rso` (2 Chronicles 36:24 is 37:1),
  whatever the scheme of 2 Chronicles.
- In `verses`, `chapter` is at most 200 and `verse` at most 1000. A file with a
  larger number in a row of a book from `books` is not a valid module.
- A row of `verses` is a piece of a chapter: text that starts at `verse` with
  the letter `part` and ends at `verse_end` with the letter `part_end`. An
  empty `part` is the whole verse; otherwise it is the letter of a part of
  the verse as the source marks it (`a`, `б`): one letter of `[a-zа-я]`.
  `verse_end` NULL is a piece within one verse, and then `part_end` is empty;
  with `verse_end` the piece is merged verses, and `part_end` is the part of
  the last verse (empty: the whole verse). `verse_end` is at most `verse` +
  200, and greater than `verse`: a piece within one verse has no `verse_end`.
  A file with a `verse_end` more than 200 above its `verse` is not a valid
  module.
- `position` is the place of the piece in the chapter, from 0, and the reader
  shows the pieces in that order: a translator may set verses out of the
  numbers or divide a verse into pieces in different places. Zechariah 4 in
  some editions reads 1–5, 6a, 10b–14, 6b–10a: four rows with `position` 0 to
  3, and `(verse, part)` of `(1, '')`, `(6, 'a')`, `(10, 'b')` and `(6, 'b')`;
  the last two have `verse_end` 14 and 10 and `part_end` '' and `a`. Pieces
  of one verse are never joined by a reader, even if they stand apart.
- Pieces do not overlap. Sort the pieces of a chapter by `(verse, part)`,
  the empty part before any letter, and compare pairs as pairs: the end of a
  piece, `(verse_end, part_end)` or, with no `verse_end`, `(verse, part)`,
  is strictly less than the `(verse, part)` of the next piece. So `1–6`
  before `6b`, and `6b–10a` before `10b`, are valid; `1–7` before `6`, and
  `1–6b` before `6b`, are not. A whole verse may be followed by its lettered
  pieces, as additions to a book (`29` then `29a` in the Greek Esther, or
  Esther `1` then `1a`). A file whose pieces overlap, with a part that is not
  one letter, with `part_end` without `verse_end`, or with a `verse_end` not
  greater than `verse` is not a valid module (`BadPiece` of
  `checkModuleFile`). A `verse_end` that is not an integer is read as NULL.
- Heading kinds: `major` is a heading above several sections, `section` a
  section heading, `title` a title that is part of the text, such as a psalm
  title, `parallel` a line of parallel places under a heading, such as
  `(Mk 1:1–8; Lk 3:1–9)`, with the places as `<x>` links (USFM `\r`, `\sr`
  at level 2 and `\mr` at level 1). A heading stands above the piece that
  starts at its `verse` and `part`; headings above one piece go in
  `position` order. A reader skips a heading of a kind it does not know.
- `intros` holds book introductions and exists only when some book has one. A
  part is a `title`, a `paragraph` or an `item`; the parts of a book go in
  `position` order and stand before the first chapter of the book. An `item`
  is a line of a list, such as a list of abbreviations: a paragraph without a
  first-line indent. In USFM it is `\ili`, `\ili1`, `\ili2` and so on. A
  reader skips a part of a kind it does not know, and a reader of an earlier
  version ignores the table. Footnotes of an introduction are in `footnotes`
  with `chapter` 0 and `verse` 0; the `<f id>` in the text of a part refers to
  them like any other.
- The lines of a book title, as the edition prints it above the first
  chapter, are parts of kind `bookTitle` and `bookSubtitle` at the start of
  the introduction. `bookTitle` is the main line (`\mt` or `\mt1` in USFM),
  `bookSubtitle` a smaller one (`\mt2`, `\mt3` and so on): «Первая книга
  Моисея» above «Бытие». They go in `position` order, so a smaller line may
  stand above or below the main one, and like other parts they may carry
  footnotes. A reader that knows them shows them in place of `books.title`;
  `books.title` stays the one-line title for lists and for readers of an
  earlier version, which skip these parts. The preface has no title lines:
  `\mt` in the `FRT` file is dropped.
- Rows of `intros` with `book` `FRT` are the preface of the module: the front
  matter of the edition, which stands before all books — a title page, a
  foreword. `FRT` is the USFM code of front matter; there is no such row in
  `books`. The preface has the same kinds of parts in `position` order. A
  reader shows it apart from the text, not before a book; a reader that does
  not know it never asks for the book `FRT`.
- Footnotes of the preface are rows of `footnotes` with `book` `FRT`,
  `chapter` 0 and `verse` 0; the `<f id>` in the preface refers to them. Their
  `id` differs from the ids of footnotes of books. A reader that does not know
  them never asks for the book `FRT` and shows the preface without its
  footnotes.
- The preface may be split into articles, each under its own name. A part of
  kind `article` is the name of an article: the article is the parts after it
  up to the next `article` part. Parts before the first name form an article
  without a name. A reader that does not know the kind skips the names and
  shows the preface as one text. A book introduction has no `article` parts.
  In USFM an article starts with `\periph <name>` in the `FRT` file;
  attributes after `|` other than `x-author` (below) are dropped, and
  `\periph` in a book is read as a title.
- A part of kind `author` right after the name of an article names its author,
  for an article that is not by the author of the module. It is not a part of
  the text of the article: a reader may show it beside the name. In USFM it is
  the attribute `x-author` of `\periph`:
  `\periph Foreword|id="foreword" x-author="John Smith"`. A reader that does
  not know the kind skips it. A book introduction has no `author` parts.
- `verse_labels` holds pieces that a printed edition marks otherwise than
  with a number, and exists only when some piece has a label. A piece with a
  row here shows no number in the text; a label that is not empty stands at
  the end of the piece, before the punctuation that ends it, in italics and
  square brackets. The Synodal edition marks the verses of the Prayer of
  Manasseh this way: 2 Chronicles 36:24 ends with *[а]* (`праведного [а],`),
  36:35 has no number and no label. The verse keeps its number as its place:
  references, search and the verse list use it. `verse` and `part` are the
  `verse` and `part` of a row of `verses`. A reader of an earlier version
  ignores the table and shows the numbers.
- `verse_numbers` holds verse numbers as a printed edition prints them, where
  they are not the plain number or range, and exists only when some piece has
  one. The text shows `number` in place of the number of the piece. A verse
  split between two ranges is the case: where an edition prints Matthew
  1:1–6а and 6б–11, the file has the pieces `1–6а` and `6б–11`: rows
  `(1, '')` with `verse_end` 6 and `part_end` `а`, and `(6, 'б')` with
  `verse_end` 11. The numbers are then the plain labels of the pieces and
  the table needs no row; it holds a number only where the print differs
  from them.
  The piece keeps its numbers as its place: references, search and the verse
  list use them. `verse` and `part` are the `verse` and `part` of a row of
  `verses`. A piece in `verse_labels` shows no number, and its row here is
  not used. A reader of an earlier version ignores the table and shows the
  numbers.
- A comment covers the place from `chapter`:`verse` to `chapter_end`:
  `verse_end`; without `chapter_end` it ends in the same chapter, without
  `verse_end` it is one verse. A reader finds comments by the chapter where
  they start. A cross reference goes from `verse` (to `verse_end`) of `book` to
  the place `to_*`, with the same rule for the end; a larger `votes` means a
  more fitting reference. `chapter` 0 is an article on the whole book, `verse`
  0 an article on the whole chapter; a range may start there. A commentary or
  cross reference module has at least one record with a book code the reader
  knows.
- A footnote kind is `note` or `crossref`. `caller` is the footnote mark as the
  source gives it; an empty string means no mark. A footnote whose `<f id>` is
  in the text of a heading is stored with the `chapter` and `verse` of the
  verse below that heading.

### Version 1

A file of version 1 has the same tables except these, which have no `part`,
`part_end` and `position` in `verses` and no `part` in `headings`,
`verse_labels` and `verse_numbers`:

```sql
CREATE TABLE verses (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  verse_end INTEGER,             -- last of merged verses; NULL: one verse
  text TEXT NOT NULL,
  PRIMARY KEY (book, chapter, verse)
) WITHOUT ROWID;
-- headings: PRIMARY KEY (book, chapter, verse, position)
-- verse_labels, verse_numbers: PRIMARY KEY (book, chapter, verse)
```

A reader reads a version 1 file as pieces without parts: a row is a piece,
its place in the chapter is its `verse`, and the pieces go in the order of the
numbers. `verse_end` there is greater than `verse`, at most `verse` + 200, and
less than the `verse` of the next row of the same chapter; a reader reads any
other `verse_end` as NULL, and such a file is still a valid module. A version
1 file is not rewritten: a version 2 reader opens it, and a version 1 reader
rejects a file of version 2 as newer. Matthew 1:1–6а and 6б–11 in version 1
is the rows 1–5 and 6–11 with `verse_numbers` `1–6а` and `6б–11`, the text of
6а in the first.

### `meta` keys

The first five keys are required.

| key | value |
|---|---|
| `type` | `bible`, `commentaries`, `crossreferences` |
| `abbreviation` | the abbreviation the module is installed under |
| `name` | name in the module's language |
| `language` | the shortest BCP 47 tag: `ru`, `en`, `grc`; `und` if unknown |
| `direction` | `ltr` or `rtl` |
| `citation` | how a quotation names the translation after the place, in the module's language: `пер. С. С. Аверинцева` in «(Мф 1:1, пер. С. С. Аверинцева)»; without it, `name` |
| `script` | ISO 15924 code: `Cyrl`, `Hebr`; may be absent |
| `license` | `PD`; any Creative Commons license as its SPDX-style id `CC-<terms>-<version>`, such as `CC-BY-4.0`, `CC-BY-SA-4.0`, `CC-BY-ND-4.0`, `CC-BY-NC-4.0`, `CC-BY-NC-SA-4.0` or `CC-BY-NC-ND-4.0`; `redistributable` (the source allows redistribution without naming a license), `unknown` (a user's own file); `unknown` if absent. CC0 and the Public Domain Mark are written `PD`. A jurisdiction port of a Creative Commons license is written without the jurisdiction: `by-nc/2.5/in` is `CC-BY-NC-2.5` |
| `copyright` | rights holder and copyright notice as given by the source |
| `description` | description of the module as given by its source |
| `source` | where the module comes from: `ebible:<translationId>` for a translation from eBible.org, `crosswire:<module>` for a module of CrossWire (`crosswire:Clarke`), `edition:<id>` for an edition kept in the catalog repository (`edition:russyn`); other sources may use their own value |
| `source_url` | page of the source |
| `version` | module version, see "Versions": `YYYY-MM-DD`, for catalog modules the eBible.org `UpdateDate`, for a CrossWire module its `SwordVersionDate`, or for an edition the date of the catalog run, optionally followed by a revision `.N` |
| `created` | date the file was written, `YYYY-MM-DD` |
| `catalog`, `catalog_id` | the catalog and the module id in it; absent in a user's own files |
| `chapter_word`, `chapter_word_psalms` | the module's words for "Chapter" and "Psalm" |
| `numbering` | commentaries and cross references: verse numbering of their references, `eng` or `rso` |
| `paragraphs` | `1` if verses contain `<p/>` |
| `generator` | what wrote the file: `catalog_builder 0.1.0`, `hisbible 1.1.0` |

Values are text. Optional keys with no value (absent or blank) are not written,
and a reader treats a blank value as absent. A reader keeps unknown keys as
they are.

### Versions

A module version is a date `YYYY-MM-DD`, optionally followed by `.N`, a
revision: N is an integer from 1, without leading zeros. Examples:
`2025-03-04`, `2025-03-04.1`, `2025-03-04.2`. The date must exist in the
calendar. For a catalog module the date is the eBible.org `UpdateDate` of the
translation; for a module converted from CrossWire it is the `SwordVersionDate`
in the `.conf` of the CrossWire module; for an edition kept in the catalog
repository it is the date of the catalog run that built it. A revision is a
rebuild by the catalog with the same date, for example after a fix in the
builder or, for a CrossWire module, from a new archive with the same
`SwordVersionDate`: `2025-03-04` → `2025-03-04.1` → `2025-03-04.2`. A new date
starts again from the bare date. An edition built again on the same day, or
when its previous version has a later date, gets the next revision of the
previous version, so its version never goes back.

Readers compare versions only for inequality and show only the date part. The
function `moduleVersionDate` of `hisbible_format` checks a version and returns
its date part. The same rule applies to the `version` of an index entry.

### Example

A Bible with Genesis 1:1–2 and Psalm 3, where Psalm 3 has a title above verse
1, a footnote on verse 2, and verses 4–5 merged:

```sql
PRAGMA application_id = 1214857833;
PRAGMA user_version = 2;
-- CREATE TABLE statements of the schema above
INSERT INTO meta VALUES
  ('type', 'bible'), ('abbreviation', 'TST'), ('name', 'Test Bible'),
  ('language', 'en'), ('direction', 'ltr'), ('script', 'Latn'),
  ('license', 'PD'), ('copyright', 'Public Domain'),
  ('source', 'ebible:engtst'), ('version', '2025-03-04'),
  ('created', '2026-10-25'), ('paragraphs', '1'),
  ('generator', 'catalog_builder 0.1.0');
INSERT INTO books VALUES
  (1, 'GEN', 'Gen', 'Genesis', 'The First Book of Moses', 'eng', NULL),
  (2, 'PSA', 'Ps', 'Psalms', NULL, 'eng', NULL);
INSERT INTO verses VALUES
  ('GEN', 1, 0, 1, '', NULL, '',
   'In the beginning God created the heavens and the earth.'),
  ('GEN', 1, 1, 2, '', NULL, '', '<p/>The earth was formless and empty.'),
  ('PSA', 3, 0, 1, '', NULL, '', 'Yahweh, how my adversaries have increased!'),
  ('PSA', 3, 1, 2, '', NULL, '',
   'Many there are who say of my soul<f id="1" c="a"/>, ...'),
  ('PSA', 3, 2, 4, '', 5, '',
   'I cry to Yahweh with my voice. <l i="1"/>I laid myself down and slept.');
INSERT INTO headings VALUES
  ('PSA', 3, 1, '', 0, 'title', 1,
   'A Psalm by David, when he fled from Absalom his son.');
INSERT INTO footnotes VALUES
  (1, 'PSA', 3, 2, 'note', 'a', 'Or, <em>life</em>');
```

## Markup

The text of a verse, a heading, and a footnote is a string with a small set of
tags. Everything outside tags is text as is; whitespace is significant.

| tag | meaning |
|---|---|
| `<p/>` | paragraph break |
| `<p m="1"/>` | paragraph break where the paragraph goes on with the sentence before it, after a quotation or poetry lines (USFM `\m`); it is printed without a first-line indent |
| `<p b="1"/>` | paragraph break after a blank line (USFM `\b`): a section break in prose or a stanza break in poetry; combines with `m="1"` |
| `<l/>`, `<l i="1"/>` … `<l i="4"/>` | new poetry line with indent 0..4 |
| `<wj>…</wj>` | words of Christ |
| `<add>…</add>` | words added by the translators |
| `<em>…</em>` | emphasis |
| `<nd>…</nd>` | divine name |
| `<qt>…</qt>` | quotation |
| `<n>…</n>` | note inside the text |
| `<h>…</h>` | heading inside the text |
| `<w s="H7225 H853" m="HNcfsa">…</w>` | a word with Strong numbers (`s`, space separated) and morphology (`m`); both attributes are optional |
| `<f id="12" c="a"/>` | footnote reference: `id` of a `footnotes` row, `c` the mark |
| `<x r="MAT.1.1">…</x>` | link to a place, `r` in the form of `ref:` without the prefix, in the numbering of this module |

Entities are `&amp;`, `&lt;`, `&gt;`, and `&quot;`. Style tags may nest.

Readers are tolerant: an unknown tag is dropped and its text kept; an unclosed
tag is closed at the end; an extra closing tag is skipped; `<f>` without a
numeric `id` is dropped; `<x>` without a readable `r` keeps its text; an indent
outside 0..4 is clamped. A reader that does not use Strong numbers shows a
`<w>` word as its text.

## Links in commentaries

The text of a commentary is HTML as given by its source. Links inside it use
two forms:

- `ref:<CODE>.<chapter>.<verse>` for a verse and
  `ref:<CODE>.<chapter>.<verse>-<CODE>.<chapter>.<verse>` for a range, where
  `<CODE>` is a book code as in `books.code`: `ref:JHN.3.16`,
  `ref:GEN.1.1-GEN.2.3`;
- `strong:<H|G><number>` for a Strong number: `strong:H7225`, `strong:G26`.

Converters rewrite links of the source into these forms. Other links lose their
`href`; their text stays.

## Index

The catalog is described by `index/index.json` in this repository. HisBible
reads it from
`https://raw.githubusercontent.com/vi-k/hisbible-catalog/main/index/index.json`.
Another catalog is the same file anywhere: module addresses in it are full
URLs. HisBible itself reads only this catalog, and takes module and font files
only from the releases of this repository: a `url` that does not start with
`https://github.com/vi-k/hisbible-catalog/releases/download/` drops its entry.

```json
{
  "format": 1,
  "catalog": "hisbible",
  "name": "HisBible",
  "updated": "2026-11-01",
  "modules": [
    {
      "id": "russyn", "type": "bible", "source": "ebible",
      "abbreviation": "russyn",
      "name": "Синодальный перевод", "description": "…",
      "language": "ru", "languageName": "Русский",
      "languageNameEnglish": "Russian", "script": "Cyrl", "direction": "ltr",
      "license": "PD", "copyright": "Public Domain",
      "books": {"ot": 39, "nt": 27, "dc": 0},
      "size": 4567890, "sha256": "…",
      "url": "https://github.com/vi-k/hisbible-catalog/releases/download/build-2026-11-01/russyn-2025-03-04.hb",
      "version": "2025-03-04", "moduleFormat": 1,
      "generator": "catalog_builder 0.3.0"
    }
  ],
  "fonts": {
    "Ethi": {
      "family": "Noto Sans Ethiopic", "license": "OFL-1.1",
      "size": 512345, "sha256": "…",
      "url": "https://github.com/vi-k/hisbible-catalog/releases/download/fonts/NotoSansEthiopic-Regular-86b9c07c.ttf"
    }
  },
  "withdrawn": [
    {"id": "xyz", "abbreviation": "xyz", "name": "…", "since": "2026-12-01"}
  ]
}
```

- `format` is the index version; it grows only with an incompatible change. A
  client that finds an index newer than it knows treats the catalog as
  unavailable and asks the user to update the app.
- `moduleFormat` is the file format version of the module. A client hides
  modules with a `moduleFormat` newer than it knows and modules of an unknown
  `type`. Unknown fields are skipped.
- `type` is `bible` for the translations of eBible.org and the editions of this
  repository, and `commentaries` for the commentaries converted from CrossWire.
  A commentaries entry has the same fields; its `id` is
  `crosswire-<module in lowercase>` (`crosswire-kd`), so it never meets a
  `translationId` of eBible.org.
- `source` says where the module comes from: `ebible` for a translation of
  eBible.org, `crosswire` for commentaries converted from CrossWire, `edition`
  for an edition kept as USFM in this repository (`editions/<id>/`, see
  `README.md`). The builder always writes it. An entry without it comes from an
  index written before the field: it is `crosswire` when its `id` starts with
  `crosswire-` and `ebible` otherwise.
- `books` counts the books of the Old Testament, the New Testament, and the
  deuterocanon; for commentaries, the books that have comments or articles.
  `size` and `sha256` describe the file at `url`. `sha256` is 64 lowercase hex
  digits.
- `description` and `copyright` of a module are optional: the field is left out
  when the source gives no value.
- `version` follows "Versions" above; a client drops a module entry whose
  `version` is not a version. A module has an update when its `version` in the
  index differs from the installed one.
- `generator` names the builder version that produced the module file, as the
  `generator` key of its `meta` (`catalog_builder 0.3.0`). The builder rebuilds
  a module of another `generator` with a new `version`; an entry without the
  field comes from a builder that did not write it. A reader ignores the field.
- `fonts` maps ISO 15924 script codes to fonts for scripts that system fonts
  may lack. The field is optional; another catalog may leave it out.
- `withdrawn` lists modules removed from the catalog and the date of removal.
- HisBible asks for the index at most once a day, with `If-None-Match` and the
  previous `ETag`.
