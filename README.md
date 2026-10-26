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
dart run catalog_builder:build [--csv <path or url>] [--limit <N>] [--dry-run] [--work <dir>]
dart run catalog_builder:build --one <zip> --csv <csv> [--out <file>]
dart run catalog_builder:build --apply-deletions <deletions.json>
```

- Without `--one` or `--apply-deletions`, the command builds the catalog. It
  publishes through `gh release` (credentials from `GH_TOKEN`) and writes
  `index/index.json`, `sources/sources.lock.json`, `out/report.md`, and
  `out/deletions.json`, the release files the new index no longer uses.
  `--limit` caps the number of builds in one run, and the rest wait for the
  next run; `--work` is the folder for downloaded archives and built modules
  (default `out/work`).
- `--dry-run` publishes nothing and writes the same four files to
  `out/dry-run/`. It still downloads from eBible.org and prints the files a
  real run would upload.
- `--apply-deletions` deletes the files listed in `out/deletions.json`. Run it
  only after the new index is pushed, so the published index never points to a
  deleted file. Deleting a file that is already gone is not an error.
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
   workflow, which commits and pushes `index/` and `sources/` itself and then
   applies the deletions. Or run `dart run catalog_builder:build` locally,
   commit and push `index/` and `sources/`, and only then run
   `dart run catalog_builder:build --apply-deletions out/deletions.json`. A dry
   run first shows the files the run would upload.
3. The run downloads the archive from eBible.org again, uploads it to
   `sources-<date>`, writes a new lock entry, and rebuilds the module into
   `build-<date>`. If the old module file is in another release, it goes to
   `out/deletions.json` and is deleted by `--apply-deletions`. If the module
   was last built the same day, the release and file name are the same: the
   upload overwrites the file (`--clobber`), the URL stays, and nothing goes to
   `out/deletions.json`.
4. The old source copy is not in `out/deletions.json`, because the run no
   longer knows it. If its release and file name differ from the new lock
   entry, delete it by hand, with the `release` and `asset` of the deleted
   entry:

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
