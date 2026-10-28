# hisbible-catalog

The HisBible module format and a catalog of free Bible translations from
eBible.org.

- `packages/hisbible_format` is a pure Dart package: the book list, verse
  numbering schemes, verse markup, and reading and writing module files.
- `FORMAT.md` describes the module file format, the markup, and the catalog
  index.

## Building the catalog

`packages/catalog_builder` builds the catalog: it reads
`https://ebible.org/Scriptures/translations.csv`, takes the translations marked
`Redistributable` and downloadable (minus `exclude` in `overrides.json`),
builds a module from each USFM archive, publishes the modules as GitHub release
files, and writes `index/index.json` and `sources/sources.lock.json`. The
`build` workflow runs it on the 1st of every month at 03:00 UTC and on demand.
Run the commands from the repository root after `dart pub get`:

```
dart run catalog_builder:build [--csv <path or url>] [--limit <N>] [--deadline <minutes>] [--rebuild <id>]... [--rebuild-all] [--allow-mass-withdrawal] [--dry-run] [--work <dir>]
dart run catalog_builder:build --one <zip> --csv <csv> [--out <file>]
dart run catalog_builder:build --apply-deletions <deletions.json>
```

- Without `--one` or `--apply-deletions`, the command builds the catalog. It
  publishes through `gh release` (credentials from `GH_TOKEN`) and writes
  `index/index.json`, `sources/sources.lock.json`,
  `sources/pending-deletions.json`, and `out/report.md`. `--limit` caps the
  number of builds in one run, and the rest wait for the next run; `--work` is
  the folder for downloaded archives and built modules (default `out/work`).
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
- `--dry-run` publishes and deletes nothing and writes the same four files to
  `out/dry-run/`. It still downloads from eBible.org and prints the files a
  real run would delete and upload.
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
every module the run takes, for example after a change to how the builder
writes modules, pass `--rebuild-all`; in the workflow, tick `rebuild_all`. Each
module then goes out as its next revision, as with `--rebuild`, so the whole
catalog is offered to the app as updates, and a run with a `--limit` or a
deadline will not reach all of them.

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

## License

The code is under the MIT License (see `LICENSE`). Third-party notices are in
`packages/hisbible_format/NOTICE`. Bible modules keep the licenses of their
translations.

The releases of this repository also republish files of others:

- the `fonts` release holds Noto fonts, under the SIL Open Font License 1.1
  (OFL-1.1), which each font file carries;
- the `sources-<date>` pre-releases hold the USFM archives of eBible.org as
  they were downloaded, unchanged, under the terms of each translation.
