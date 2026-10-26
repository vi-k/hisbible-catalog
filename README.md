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
dart run catalog_builder:build [--csv <path or url>] [--limit <N>] [--deadline <minutes>] [--allow-mass-withdrawal] [--dry-run] [--work <dir>]
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
  `-`, or whose `UpdateDate` is not `YYYY-MM-DD`, is skipped and listed in the
  report; the module built from it earlier stays as it is.
- A run withdraws at most 20 modules, or 5% of the catalog if that is more. If
  more translations disappear from `translations.csv`, the run withdraws none
  of them, deletes nothing of theirs, and says so in the report. If eBible
  really withdrew them, run the build again with `--allow-mass-withdrawal` (in
  the workflow, the `allow_mass_withdrawal` input).
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

A module is rebuilt only when its translation gets a new `UpdateDate` on
eBible.org. If the index entry and the `sources/sources.lock.json` entry of a
translation both carry its current `UpdateDate`, the module stays as it is. So
a change to `overrides.json` (for example, a new abbreviation) or to the
builder does not reach modules that are already published, and there is no flag
to force a rebuild. To rebuild one module:

1. Delete the translation's entry from `sources/sources.lock.json`. Keep its
   entry in `index/index.json`.
2. Run the build. Either push the change to `main` and start the `build`
   workflow, which commits and pushes `index/` and `sources/` itself. Or run
   `dart run catalog_builder:build` locally, then commit and push `index/` and
   `sources/`. A dry run first shows the files the run would upload.
3. The run downloads the archive from eBible.org again, uploads it to
   `sources-<date>`, writes a new lock entry, and rebuilds the module into
   `build-<date>`. If the old module file is in another release, it goes to
   `sources/pending-deletions.json`, and the next run deletes it. If the module
   was last built the same day, the release and file name are the same: the
   upload overwrites the file (`--clobber`), the URL stays, and nothing goes to
   the deletion list.
4. The old source copy is not in the deletion list, because the run no longer
   knows it. If its release and file name differ from the new lock entry,
   delete it by hand, with the `release` and `asset` of the deleted entry:

   ```
   gh release delete-asset <release> <asset> --repo vi-k/hisbible-catalog --yes
   ```

The rebuilt module keeps its `version`, the `UpdateDate`, and the app offers an
update only when `version` changes. So the new file reaches only new downloads;
people who installed the module keep the old file.

Do not delete the index entry instead: the module is then rebuilt from the
saved source copy, but its old file is not listed for deletion and stays in its
release.

## License

The code is under the MIT License (see `LICENSE`). Third-party notices are in
`packages/hisbible_format/NOTICE`. Bible modules keep the licenses of their
translations.

The releases of this repository also republish files of others:

- the `fonts` release holds Noto fonts, under the SIL Open Font License 1.1
  (OFL-1.1), which each font file carries;
- the `sources-<date>` pre-releases hold the USFM archives of eBible.org as
  they were downloaded, unchanged, under the terms of each translation.
