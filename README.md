# hisbible-catalog

The HisBible module format and a catalog of free Bible translations from
eBible.org.

- `packages/hisbible_format` is a pure Dart package: the book list, verse
  numbering schemes, verse markup, reading and writing module files, and
  reading USFM and writing a module from it.
- `FORMAT.md` describes the module file format, the markup, and the catalog
  index.

## Building the catalog

`packages/catalog_builder` builds the catalog: it reads
`https://ebible.org/Scriptures/translations.csv`, takes the translations marked
`Redistributable` and downloadable (minus `exclude` in `overrides.json`),
builds a module from each USFM archive, adds the commentaries listed in
`sources/crosswire.lock.json` (see "Commentaries from CrossWire") and the
editions in `editions/` (see "Own editions"), publishes the modules as GitHub
release files, and writes `index/index.json` and `sources/sources.lock.json`. A
row of `translations.csv` whose `translationId` is the id of an edition is not
taken: the edition builds that module. The `build` workflow runs it on the 1st
of every month at 03:00 UTC and on demand. Run the commands from the repository
root after `dart pub get`:

```
dart run catalog_builder:build [--csv <path or url>] [--limit <N>] [--deadline <minutes>] [--rebuild <id>]... [--rebuild-before <YYYY-MM-DD>] [--allow-mass-withdrawal] [--dry-run] [--work <dir>]
dart run catalog_builder:build --one <zip> --csv <csv> [--out <file>]
dart run catalog_builder:build --apply-deletions <deletions.json>
```

- Without `--one` or `--apply-deletions`, the command builds the catalog. It
  publishes through `gh release` (credentials from `GH_TOKEN`) and writes
  `index/index.json`, `sources/sources.lock.json`,
  `sources/pending-deletions.json`, `sources/editions.lock.json`, and
  `out/report.md`. `--limit` caps the number of translation builds in one run,
  and the rest wait for the next run (CrossWire commentaries and editions do
  not count toward it); `--work` is the folder for downloaded archives and
  built modules (default `out/work`).
- A run does not delete the release files that its new index no longer uses. It
  lists them in `sources/pending-deletions.json`, which is committed with the
  index. The next run deletes them at its start; by then the CDN of
  raw.githubusercontent.com serves the new index. A listed file that the
  current index or `sources/sources.lock.json` uses again is not deleted. A
  failed deletion stays in the list for the run after that.
- `--deadline` stops taking new translations that many minutes after the start;
  the translation in progress is finished, and the run writes its files as
  usual. The `build` workflow passes `--deadline 300`.
- If `translations.csv` lacks a column the builder reads, or `Redistributable`
  or `downloadable` is neither `True` nor `False`, the run fails before it
  changes anything. A row whose `translationId` is not letters, digits, `_` and
  `-`, or whose `UpdateDate` is not a real `YYYY-MM-DD` date (not
  `2026-02-30`), is skipped and listed in the report; the module built from it
  earlier stays as it is.
- A run withdraws at most 20 modules, or 5% of the catalog if that is more. If
  more translations disappear from `translations.csv`, the run withdraws none
  of them, deletes nothing of theirs, and says so in the report. It still
  writes the index, the lock and the report with all modules kept, and then
  exits with code 3. The `build` workflow commits and pushes `index/` and
  `sources/` as usual, and only then fails, naming the reason and the key. If
  eBible really withdrew them, run the build again with
  `--allow-mass-withdrawal` (in the workflow, the `allow_mass_withdrawal`
  input).
- When `gh` reports the GitHub API rate limit, the run stops at once: the
  translation in progress fails, the rest wait for the next run, and the report
  says why. A `GITHUB_TOKEN` allows about 1000 API requests an hour, and each
  module takes four or five. Build the first, full catalog in runs of about
  `--limit 200`, an hour apart.
- `--dry-run` publishes and deletes nothing and writes the same five files to
  `out/dry-run/`. It still downloads from eBible.org and CrossWire, checks the
  CrossWire archives against `sources/crosswire.lock.json`, and prints the
  files a real run would delete and upload.
- `--apply-deletions` deletes the files listed in a deletion list, for manual
  use: for example, `sources/pending-deletions.json` when no run is planned
  soon. Run it only when the pushed index has not used those files for at least
  ten minutes. Deleting a file that is already gone is not an error.
- `--one` builds one module from a USFM archive named
  `<translationId>_usfm.zip` or `<translationId>-<UpdateDate>_usfm.zip`; the
  translation is looked up in the given `translations.csv`. It ignores
  `overrides.json`.

### Rebuilding a module

A module is rebuilt by itself only when its translation gets a new `UpdateDate`
on eBible.org. To rebuild a module whose `UpdateDate` is the same, for example
after a change to `overrides.json` or to the builder, pass its translation id
to `--rebuild`; repeat the key for several modules. In the `build` workflow,
put the ids in the `rebuild` input, separated by spaces or commas. To rebuild
many modules, for example after a change to how the builder writes modules,
pass `--rebuild-before <YYYY-MM-DD>`; in the workflow, fill `rebuild_before`.
The run rebuilds, as `--rebuild` does, the modules the run takes whose current
file was built before that date (the date is in the release name `build-<date>`
of the file address; an address that cannot be read counts as older). They come
after explicit `--rebuild` ids and new or updated translations, and count
toward `--limit` and the deadline. A rebuilt module lands in the release of the
current run, so it is no longer before the date: when the run does not reach
all of them, run again with the same date and it continues where it stopped,
without rebuilding a module twice. Modules not reached are not an error: the
run exits normally, and the report says how many were rebuilt and how many are
left (a module that fails to build stays in "Failed" and in "left").

The builder also writes its version (`generator`, for example
`catalog_builder 0.3.0`) into the index entry of each module it builds. The
constant `builderVersion` grows in the same change that alters what the builder
writes into a module, and the run itself rebuilds the modules built by another
version: it queues them like `--rebuild-before` does, after explicit ids and new
or updated translations, and within `--limit` and the deadline, so they never
starve new work. Editions and commentaries of another version are rebuilt first,
like a forced rebuild. The report says how many were rebuilt and how many are
left ("Rebuild for catalog_builder 0.3.0: N rebuilt, M left"); run again to
continue.

A rebuilt module is published as the next revision of its version: `2025-03-04`
becomes `2025-03-04.1`, then `2025-03-04.2` (see "Versions" in `FORMAT.md`).
The app offers it as an update to everyone who installed the module. The run
builds it from the saved source copy in `sources/sources.lock.json`, and
downloads the archive from eBible.org only if there is no copy of the current
`UpdateDate`. The module goes to a new file, `<id>-<version>.hb` in
`build-<date>`, and the old file goes to `sources/pending-deletions.json` as
usual. When eBible publishes a new `UpdateDate`, the version starts again from
the bare date.

Rebuilds come first in the run, before new and updated translations, and count
toward `--limit`. An id that the run does not take (not in `translations.csv`,
not redistributable, excluded or skipped) is listed under "Failed" in the
report. The ids are not remembered between runs: a rebuild that is left out by
`--limit`, the deadline or the rate limit, or that fails, must be requested
again. Such a run writes its files as usual, names the ids in the report, and
exits with code 3; the `build` workflow commits and pushes `index/` and
`sources/` and then fails, naming them.

## Built-in cross references

The app ships one cross-reference module of its own, built from
[OpenBible.info](https://www.openbible.info/labs/cross-references/). It is not
part of the catalog and is not published: run
`dart run catalog_builder:build --openbible <out.hb>` and take the file. The
command downloads `https://a.openbible.info/data/cross-references.zip`, reads
`cross_references.txt` from the archive in memory, drops links with negative
votes, links to themselves and places outside the English numbering (`eng`),
and writes a `crossrefs` module, `numbering` `eng`, `license` `CC-BY-4.0`. Its
`version` is the date of the archive's `Last-Modified` header.

The first run writes the archive's sha256 and `Last-Modified` date to
`sources/openbible.lock.json`. A later run with another archive stops with an
error and leaves the lock and the module as they were; check the new data and
run again with `--accept-new-source` to take it. The same archive keeps the
version from the lock.

## Commentaries from CrossWire

Two public-domain commentaries of the
[CrossWire SWORD](https://www.crosswire.org/sword/) library can be built into
`commentaries` modules: `Clarke` (Adam Clarke) and `KD` (Keil and Delitzsch).
`dart run catalog_builder:build --crosswire <module> <out.hb>` builds one into
a file and records its archive in `sources/crosswire.lock.json`; the catalog
run builds and publishes every module recorded there. The command downloads
`https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/<module>.zip`
and reads the module's `.conf` and its zCom or zCom4 files from the archive in
memory. The module must be OSIS, UTF-8, ZIP-compressed, in the KJV
versification and `Public Domain`; anything else stops with an error and writes
nothing. The module gets `numbering` `eng`, `license` `PD`, `source`
`crosswire:<module>`, and its `version` is the `SwordVersionDate` of the
`.conf`.

OSIS markup becomes HTML, and references become links. The record of verse 1
often begins with an introduction to the book or the chapter; it is split off
into a book article (chapter 1) or a chapter article: in `Clarke` the comment
on the verse begins at the bold label "Verse 1", in `KD` at a paragraph opened
by a reference to verse 1. In `KD` a record often sits on the last verse of the
passage it explains, and the passage is named by the single reference of its
first paragraph; when that reference is in the same chapter and covers the
record's verses, the comment takes its range. The command prints how many
comments, articles and links it wrote.

The first run of each module writes its archive's URL, sha256, version and date
to `sources/crosswire.lock.json`; the entries of other modules stay as they
are. A later run with another archive stops with an error and leaves the lock
and the module as they were; check the new data and run again with
`--accept-new-source` to take it.

### Commentaries in the catalog

To add a module to the catalog, run `--crosswire <module> <out.hb>` (with
`--accept-new-source` for a new archive of a module already listed) and commit
`sources/crosswire.lock.json`. The catalog run never takes a new archive
itself, in the workflow or not. For every module in the lock it downloads the
archive from CrossWire and checks its sha256 against the lock; an archive that
differs, or that cannot be downloaded, fails the module in the report, and the
module already in the index stays there as it was. The commentaries come first
in the run and do not count toward `--limit`; they are not withdrawn for being
absent from `translations.csv`, only when their entry leaves the lock.

A commentaries module enters the index with `type` `commentaries`, the id
`crosswire-<module in lowercase>` (`crosswire-clarke`, `crosswire-kd`),
`language` `en`, and the abbreviation of the module. Like a translation, its
archive is saved to `sources-<date>` and listed in `sources/sources.lock.json`
(as `<id>-<SwordVersionDate>.zip`), and the module goes to `build-<date>` as
`<id>-<version>.hb`. The version is the `SwordVersionDate`. A module whose
version has that date and whose saved copy is of the same archive is left as it
is. It becomes the next revision (`.1`, `.2`…) when an accepted archive has the
same `SwordVersionDate`, or when its id is given to `--rebuild`, or when it was
built before `--rebuild-before`; a new `SwordVersionDate` starts again from the
bare date. The report lists the comments, articles and links of each
commentaries module built.

## Own editions

An edition is a translation kept in this repository as USFM, corrected here,
and built into a catalog module by the catalog run. It lives in
`editions/<id>/`:

- `edition.json` gives the module's `id`, `abbreviation`, `name`,
  `description`, `language`, `languageName`, `languageNameEnglish`, `script`,
  `direction`, `license`, `copyright`, and `sourceUrl`; all of them are
  required. The `id` is the name of the folder, and `direction` is `ltr` or
  `rtl`.
- `usfm/` holds the books, one USFM file each, ending in `.usfm` or `.sfm`;
  other files there are not read.
- `spelling.tsv` is the spelling table: one `old<TAB>new` pair per line, in
  lowercase and without stress marks; empty lines and lines starting with `#`
  are skipped. The USFM keeps the spelling of its source, and the builder
  replaces whole words by the table, keeping a capital letter and stress marks
  and leaving markers and attributes alone. A word is taken out of the modern
  spelling by deleting its line.
- `CHANGES.md` is the log of changes to the text of the source: the verse, the
  reading of the source, and the reading taken. Every change of the text has a
  line there. Stress marks, notes and cross references are not listed; the
  edition's `README.md` describes them.
- `README.md` says what the edition is based on and what its brackets, italics
  and notes mean.

To correct the text, edit the USFM file, add a line to `CHANGES.md`, and
commit. The next catalog run sees that the edition changed and rebuilds the
module; nothing else has to be run. To check a change first, build the module
into a file:

```
dart run catalog_builder:build --edition editions/<id> <out.hb>
```

The command publishes nothing. It prints the number of verses, the books of the
Old Testament, the New Testament and the deuterocanon, the words the spelling
table replaced, the cross references that became links and those that did not,
and how many books are in each numbering scheme, followed by warnings. A module
that would lose text (an unknown marker, a dropped fragment), keep markup in
its text, or have a different number of verses than there are `\v` markers is
not written: the command lists the reasons and exits with code 1.

### Editions in the catalog

The catalog run builds the editions first, before the CrossWire commentaries,
and they do not count toward `--limit`. The module of an edition takes the
place of the eBible module with the same id: the id stays, the eBible row is
not taken, and the module is never withdrawn because eBible drops that row. Its
index entry has `source` `edition`.

The run records a digest of each edition folder (`edition.json`,
`spelling.tsv`, and the files of `usfm/`) in `sources/editions.lock.json`. An
edition is rebuilt when its digest differs from the recorded one, when its
index entry does not come from the edition yet, when its id is given to
`--rebuild` (in the workflow, the `rebuild` input), or when it was built before
`--rebuild-before`; otherwise its entry stays as it is. The version of the
module is the date of the run. When the previous version has the same date or
a later one, as after a second build on the same day, the version is the next
revision of the previous one (`.1`, `.2`…): it never goes back. The run date is
later than the date of the eBible module it replaces, so the app offers the
edition as an update to everyone who installed that module.

The module goes to `build-<date>` as `<id>-<version>.hb`. The old module file
goes to `sources/pending-deletions.json`, and so does the saved eBible source
copy with the same id, which leaves `sources/sources.lock.json`. An edition
that fails to build is listed under "Failed" in the report; its index entry and
its digest stay as they were, the next run tries again, and the run ends with
exit code 3, so the workflow commits the index and then turns red with
"Edition not built". The same goes for a
folder of `editions/` that cannot be read (a broken `edition.json`, no `usfm/`
or `spelling.tsv`), known by the `id` in its `edition.json` if that can be read
and by the folder name otherwise, and for an id that two folders declare:
neither of them is built. Such an id still keeps the eBible row out and is not
withdrawn, and the rest of the run goes on. The report lists each built edition
under "Editions" with the numbers `--edition` prints except the book counts:
verses, words replaced, links, unresolved cross references, and numbering
schemes. Its warnings go under it; an edition that was not built is listed
there with the reasons.

## License

The code is under the MIT License (see `LICENSE`). Third-party notices are in
`packages/hisbible_format/NOTICE`. Bible modules keep the licenses of their
translations.

The releases of this repository also republish files of others:

- the `fonts` release holds Noto fonts, under the SIL Open Font License 1.1
  (OFL-1.1), which each font file carries;
- the `sources-<date>` pre-releases hold the USFM archives of eBible.org as
  they were downloaded, unchanged, under the terms of each translation.

The built-in cross-reference module (see "Built-in cross references") is made
from OpenBible.info data under CC BY 4.0; the module carries the attribution in
its `copyright`.
