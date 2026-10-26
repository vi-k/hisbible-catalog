# HisBible module format

A HisBible module is one SQLite database file with the extension `.hb`. One
file holds one module: a Bible translation, commentaries, or cross references.
This document describes version 1 of the file format, the verse markup, links
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
- `PRAGMA user_version` is the format version, currently `1`. A reader that
  knows version `N` opens files of versions `1..N` and rejects newer ones.
- Adding an optional `meta` key, a table, or a column does not change the
  version: readers skip what they do not know. The version grows only with an
  incompatible change.
- A module contains only tables and their indexes: no views, triggers or
  virtual tables. A reader refuses a file with any other schema object.

### Schema of version 1

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE books (
  position INTEGER PRIMARY KEY,  -- order of books in the module, from 1
  code TEXT NOT NULL UNIQUE,     -- USFM code or H<number>
  short_name TEXT NOT NULL,      -- "Gen", "Быт"
  long_name TEXT NOT NULL,       -- "Genesis", "Бытие"
  title TEXT,                    -- full title (\toc1)
  scheme TEXT NOT NULL,          -- eng | org | rso | rsc
  color INTEGER                  -- 0xRRGGBB; NULL: the reader's default color
);
CREATE TABLE verses (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  verse_end INTEGER,             -- last of merged verses; NULL: one verse
  text TEXT NOT NULL,            -- markup, see "Markup"
  PRIMARY KEY (book, chapter, verse)
) WITHOUT ROWID;
CREATE TABLE headings (
  book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  position INTEGER NOT NULL,     -- order above one verse, from 0
  kind TEXT NOT NULL,            -- major | section | title
  level INTEGER NOT NULL,        -- 1..3
  text TEXT NOT NULL,            -- markup without <p/> and <l/>
  PRIMARY KEY (book, chapter, verse, position)
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
| `bible` | `meta`, `books`, `verses`, `headings`, `footnotes` |
| `commentaries` | `meta`, `comments` |
| `crossreferences` | `meta`, `crossrefs` |

Notes:

- `book` columns hold book codes: the USFM code (`GEN`, `PSA`, `MAT`) or
  `H<number>` for a book that has no USFM code; the number is a book number of
  the HisBible book list (`BookCatalog` in `hisbible_format`).
- A reader skips verses of a book that is not in `books`, and books whose code
  it does not know. A Bible has at least one verse of a book from `books`.
- `scheme` is the verse numbering of the book, named as the SIL versification
  files: `eng` (English), `org` (original: a psalm title is verse 1), `rso`
  (Russian Synodal, full edition), `rsc` (Russian Synodal, canonical edition).
- In `verses`, `chapter` is at most 200 and `verse` at most 1000. A file with a
  larger number in a row of a book from `books` is not a valid module.
- Merged verses are one row: `verse` is the first verse, `verse_end` the last.
  `verse_end` is greater than `verse`, at most `verse` + 200, and less than the
  `verse` of the next row of the same chapter. A reader reads any other
  `verse_end` as NULL (one verse). A file with a `verse_end` more than 200
  above its `verse` is not a valid module.
- Heading kinds: `major` is a heading above several sections, `section` a
  section heading, `title` a title that is part of the text, such as a psalm
  title. Headings above one verse go in `position` order.
- A comment covers the place from `chapter`:`verse` to `chapter_end`:
  `verse_end`; without `chapter_end` it ends in the same chapter, without
  `verse_end` it is one verse. A reader finds comments by the chapter where
  they start. A cross reference goes from `verse` (to `verse_end`) of `book` to
  the place `to_*`, with the same rule for the end; a larger `votes` means a
  more fitting reference. A commentary or cross reference module has at least
  one record with a book code the reader knows.
- A footnote kind is `note` or `crossref`. `caller` is the footnote mark as the
  source gives it; an empty string means no mark.

### `meta` keys

The first five keys are required.

| key | value |
|---|---|
| `type` | `bible`, `commentaries`, `crossreferences` |
| `abbreviation` | the abbreviation the module is installed under |
| `name` | name in the module's language |
| `language` | the shortest BCP 47 tag: `ru`, `en`, `grc`; `und` if unknown |
| `direction` | `ltr` or `rtl` |
| `script` | ISO 15924 code: `Cyrl`, `Hebr`; may be absent |
| `license` | `PD`; any Creative Commons license as its SPDX-style id `CC-<terms>-<version>`, such as `CC-BY-4.0`, `CC-BY-SA-4.0`, `CC-BY-ND-4.0`, `CC-BY-NC-4.0`, `CC-BY-NC-SA-4.0` or `CC-BY-NC-ND-4.0`; `redistributable` (the source allows redistribution without naming a license), `unknown` (a user's own file); `unknown` if absent. CC0 and the Public Domain Mark are written `PD`. A jurisdiction port of a Creative Commons license is written without the jurisdiction: `by-nc/2.5/in` is `CC-BY-NC-2.5` |
| `copyright` | rights holder and copyright notice as given by the source |
| `description` | description of the module as given by its source |
| `source` | where the module comes from: `ebible:<translationId>` for a translation from eBible.org; other sources may use their own value |
| `source_url` | page of the source |
| `version` | module version: for catalog modules, the eBible.org `UpdateDate` |
| `created` | date the file was written, `YYYY-MM-DD` |
| `catalog`, `catalog_id` | the catalog and the module id in it; absent in a user's own files |
| `chapter_word`, `chapter_word_psalms` | the module's words for "Chapter" and "Psalm" |
| `numbering` | commentaries and cross references: verse numbering of their references, `eng` or `rso` |
| `paragraphs` | `1` if verses contain `<p/>` |
| `generator` | what wrote the file: `catalog_builder 0.1.0`, `hisbible 1.1.0` |

Values are text. Optional keys with no value (absent or blank) are not written,
and a reader treats a blank value as absent. A reader keeps unknown keys as
they are.

### Example

A Bible with Genesis 1:1–2 and Psalm 3, where Psalm 3 has a title above verse
1, a footnote on verse 2, and verses 4–5 merged:

```sql
PRAGMA application_id = 1214857833;
PRAGMA user_version = 1;
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
  ('GEN', 1, 1, NULL, 'In the beginning God created the heavens and the earth.'),
  ('GEN', 1, 2, NULL, '<p/>The earth was formless and empty.'),
  ('PSA', 3, 1, NULL, 'Yahweh, how my adversaries have increased!'),
  ('PSA', 3, 2, NULL, 'Many there are who say of my soul<f id="1" c="a"/>, ...'),
  ('PSA', 3, 4, 5, 'I cry to Yahweh with my voice. <l i="1"/>I laid myself down and slept.');
INSERT INTO headings VALUES
  ('PSA', 3, 1, 0, 'title', 1, 'A Psalm by David, when he fled from Absalom his son.');
INSERT INTO footnotes VALUES
  (1, 'PSA', 3, 2, 'note', 'a', 'Or, <em>life</em>');
```

## Markup

The text of a verse, a heading, and a footnote is a string with a small set of
tags. Everything outside tags is text as is; whitespace is significant.

| tag | meaning |
|---|---|
| `<p/>` | paragraph break |
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

Entities are `&amp;`, `&lt;`, `&gt;`, and `&quot;`. Style tags may nest.

Readers are tolerant: an unknown tag is dropped and its text kept; an unclosed
tag is closed at the end; an extra closing tag is skipped; `<f>` without a
numeric `id` is dropped; an indent outside 0..4 is clamped. A reader that does
not use Strong numbers shows a `<w>` word as its text.

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
URLs.

```json
{
  "format": 1,
  "catalog": "hisbible",
  "name": "HisBible",
  "updated": "2026-11-01",
  "modules": [
    {
      "id": "russyn", "type": "bible", "abbreviation": "russyn",
      "name": "Синодальный перевод", "description": "…",
      "language": "ru", "languageName": "Русский",
      "languageNameEnglish": "Russian", "script": "Cyrl", "direction": "ltr",
      "license": "PD", "copyright": "Public Domain",
      "books": {"ot": 39, "nt": 27, "dc": 0},
      "size": 4567890, "sha256": "…",
      "url": "https://github.com/vi-k/hisbible-catalog/releases/download/build-2026-11-01/russyn-2025-03-04.hb",
      "version": "2025-03-04", "moduleFormat": 1
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
- `books` counts the books of the Old Testament, the New Testament, and the
  deuterocanon; `size` and `sha256` describe the file at `url`. `sha256` is 64
  lowercase hex digits.
- `description` and `copyright` of a module are optional: the field is left out
  when the source gives no value.
- A module has an update when its `version` in the index differs from the
  installed one.
- `fonts` maps ISO 15924 script codes to fonts for scripts that system fonts
  may lack. The field is optional; another catalog may leave it out.
- `withdrawn` lists modules removed from the catalog and the date of removal.
- HisBible asks for the index at most once a day, with `If-None-Match` and the
  previous `ETag`.
