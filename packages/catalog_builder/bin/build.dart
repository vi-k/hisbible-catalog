// Сборка каталога HisBible. Запускается из корня репозитория.
//
// Прогон каталога:
//   dart run catalog_builder:build [--csv <путь или адрес>] [--limit <N>]
//       [--dry-run] [--work <каталог>]
// Таблица переводов по умолчанию —
// https://ebible.org/Scriptures/translations.csv. Читает `index/index.json`,
// `sources/sources.lock.json`, `overrides.json` и `fonts/fonts.lock.json`
// (нет файла — пусто), собирает модули через `runCatalogBuild`, выкладывает
// их через `gh release` и пишет `index/index.json`,
// `sources/sources.lock.json`, `out/report.md` и `out/deletions.json` —
// файлы выпусков, на которые новый указатель больше не ссылается.
// `--limit` — не больше N сборок; пустое значение — без предела.
// `--dry-run` ничего не выкладывает и пишет те же четыре файла
// в `out/dry-run/`. Скачанные архивы и собранные модули лежат в `--work`,
// по умолчанию `out/work`; в настоящем прогоне архив удаляется после
// сборки, модуль — после выкладки, `--dry-run` их оставляет.
//
// Удаление старых файлов, после того как новый указатель отправлен:
//   dart run catalog_builder:build --apply-deletions <deletions.json>
//
// Один модуль:
//   dart run catalog_builder:build --one <zip> --csv <translations.csv>
//       [--out <file>]
// Перевод ищется в `translations.csv` по имени архива:
// `<translationId>_usfm.zip` или `<translationId>-<UpdateDate>_usfm.zip`.
// Без `--out` модуль `<translationId>-<UpdateDate>.hb` пишется рядом
// с архивом.
//
// Код выхода: 0 — готово, 1 — не собрано или не всё удалено,
// 64 — неверные аргументы.

import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';

Future<void> main(List<String> args) async {
  exitCode = await runBuildCli(args);
}
