// Сборка каталога HisBible. Запускается из корня репозитория.
//
// Прогон каталога:
//   dart run catalog_builder:build [--csv <путь или адрес>] [--limit <N>]
//       [--deadline <минуты>] [--rebuild <id>]...
//       [--rebuild-before <YYYY-MM-DD>] [--allow-mass-withdrawal] [--dry-run]
//       [--work <каталог>]
// Таблица переводов по умолчанию —
// https://ebible.org/Scriptures/translations.csv. Читает `index/index.json`,
// `sources/sources.lock.json`, `sources/pending-deletions.json`,
// `overrides.json` и `fonts/fonts.lock.json` (нет файла — пусто). Сначала
// удаляет файлы из `sources/pending-deletions.json`, записанные прошлым
// прогоном, потом собирает модули через `runCatalogBuild`, выкладывает их
// через `gh release` и пишет `index/index.json`,
// `sources/sources.lock.json`, `sources/pending-deletions.json` — файлы
// выпусков, на которые новый указатель больше не ссылается, их удалит
// следующий прогон, — и `out/report.md`.
// `--limit` — не больше N сборок; пустое значение — без предела.
// `--deadline` — через столько минут от запуска новые переводы не берутся.
// `--rebuild <id>` (можно повторять) — пересобрать модуль перевода, даже
// если его `UpdateDate` не изменился, и выпустить следующей правкой
// версии: `<дата>.1`, `<дата>.2`…; исходник — своя копия из
// `sources/sources.lock.json`. `--rebuild-before <дата>` — то же для взятых
// переводов, чей модуль собран раньше даты (по выпуску `build-<дата>`
// в адресе): после явных `--rebuild` и новых, в пределах `--limit` и срока;
// не дошедшие не считаются ошибкой, тот же ключ в следующем прогоне
// продолжает с них. `--allow-mass-withdrawal` — отозвать
// модули, даже если их больше предела массового отзыва. Прогон, который
// отказался от отзыва или не собрал id из `--rebuild`, пишет свои файлы
// как обычно и выходит с кодом 3. `--dry-run` ничего не выкладывает
// и не удаляет и пишет те же четыре файла в `out/dry-run/`. Скачанные архивы
// и собранные модули лежат в `--work`, по умолчанию `out/work`;
// в настоящем прогоне архив удаляется после сборки, модуль — после
// выкладки, `--dry-run` их оставляет.
//
// Удаление файлов из списка вручную:
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
// Код выхода: 0 — готово, 1 — не собрано или не всё удалено, 3 — файлы
// прогона записаны, но массовый отзыв отклонён или `--rebuild`
// не собран, 64 — неверные аргументы.

import 'dart:io';

import 'package:catalog_builder/catalog_builder.dart';

Future<void> main(List<String> args) async {
  exitCode = await runBuildCli(args);
}
