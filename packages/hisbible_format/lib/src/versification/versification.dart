import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/books/book_info.dart';
import 'package:hisbible_format/src/refs/verse_ref.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';
import 'package:hisbible_format/src/versification/eng_deutero_vrs.dart';
import 'package:hisbible_format/src/versification/rso_deutero_vrs.dart';
import 'package:hisbible_format/src/versification/vrs_data.dart';

/// Место внутри таблиц SIL: код книги SIL, глава, стих.
typedef _SilRef = (String, int, int);

/// Перевод мест между схемами нумерации SIL и распознавание схемы книг.
///
/// Каноническая схема — [VerseScheme.eng]. Переход идёт через еврейскую
/// нумерацию, в которую ведут соответствия каждого файла `.vrs`.
final class Versification {
  Versification._(this._tables);

  /// Разбирает файлы `.vrs`; схема без файла переводится тождественно.
  factory Versification.fromVrs(Map<VerseScheme, String> files) =>
      Versification._({
        for (final scheme in VerseScheme.values)
          scheme: _VrsTable.parse(files[scheme] ?? ''),
      });

  /// Шесть схем SIL из `vrs_data.dart`; разбираются при первом обращении.
  /// К `eng` и `rso` дописаны свои соответствия неканонических книг
  /// (`eng_deutero_vrs.dart`, `rso_deutero_vrs.dart`); у `eng` они стоят
  /// первыми, чтобы победить строку SIL `BAR 6:1-73 = LJE 1:1-73`.
  static final Versification standard = Versification.fromVrs({
    VerseScheme.eng: '$engDeuteroVrs\n$engVrs\n$engDeuteroLengths',
    VerseScheme.org: orgVrs,
    VerseScheme.rso: '$rsoVrs\n$rsoDeuteroVrs',
    VerseScheme.rsc: rscVrs,
    VerseScheme.lxx: lxxVrs,
    VerseScheme.vul: _vulFixed,
  });

  // Опечатка `vul.vrs.txt`: `DAG 3:52-23` вместо `DAG 3:52-53` — та же
  // строка в `eng.vrs.txt` читается `S3Y 1:30-31 = DAG 3:52-53`.
  static final String _vulFixed = _fixed(
    vulVrs,
    'DAG 3:52-23 = S3Y 1:30-31',
    'DAG 3:52-53 = S3Y 1:30-31',
  );

  // Таблица с одной поправленной строкой; строки нет — ошибка: таблицу
  // обновили, и поправку пора пересмотреть.
  static String _fixed(String table, String wrong, String right) {
    final at = table.indexOf(wrong);
    if (at < 0 || table.indexOf(wrong, at + 1) >= 0) {
      throw StateError('Поправка таблицы .vrs не на месте: $wrong');
    }

    return table.replaceFirst(wrong, right);
  }

  // Порядок схем при ничьей в распознавании. `lxx` и `vul` в нём нет: они —
  // схемы традиции и спорят за книгу, только когда [detect] их назвали.
  static const _russianOrder = [
    VerseScheme.rsc,
    VerseScheme.rso,
    VerseScheme.eng,
    VerseScheme.org,
  ];
  static const _otherOrder = [
    VerseScheme.eng,
    VerseScheme.org,
    VerseScheme.rsc,
    VerseScheme.rso,
  ];

  // Последний стих 2 Пар 36 в схемах `rsc` и `rso`; у перевода, где за ним
  // идут ещё стихи, это Молитва Манассии.
  static const _chronicles36Last = 23;

  final Map<VerseScheme, _VrsTable> _tables;

  _VrsTable get _eng => _tables[VerseScheme.eng]!;

  // Карта молитвы — из таблицы `rso`: 2 Пар 37 ↔ книга MAN.
  _VrsTable get _rso => _tables[VerseScheme.rso]!;

  /// Переводит место [ref] из схемы [from] в каноническую.
  ///
  /// У схем `rsc` и `rso` стихи 2 Пар 36 после 23-го — Молитва Манассии,
  /// как 2 Пар 37 таблицы `rso`: они ведут в книгу 145. Так же — у любой
  /// схемы при [manasseh] [ManassehHome.chronicles36], а при
  /// [ManassehHome.chronicles37] — 2 Пар 37: дом молитвы важнее схемы 2 Пар.
  VerseRef toCanonical(
    VerseRef ref,
    VerseScheme from, {
    ManassehHome manasseh = ManassehHome.book,
  }) {
    if (from == VerseScheme.eng && manasseh == ManassehHome.book) {
      return ref;
    }

    return _translate(ref, (r) {
      final prayer = _prayerToCanonical(r, from, manasseh);
      if (prayer == null && from == VerseScheme.eng) {
        return r;
      }
      final original = prayer ?? _tables[from]!.forward[r] ?? r;

      return _eng.inverse[original] ?? original;
    });
  }

  /// Переводит каноническое место [ref] в схему [to].
  ///
  /// Место книги 145 при [manasseh], отличном от [ManassehHome.book], идёт
  /// в 2 Пар 37 по карте молитвы, а для [ManassehHome.chronicles36] — дальше
  /// в 2 Пар 36 со сдвигом на 23 стиха; схема [to] тогда роли не играет.
  VerseRef fromCanonical(
    VerseRef ref,
    VerseScheme to, {
    ManassehHome manasseh = ManassehHome.book,
  }) {
    if (to == VerseScheme.eng && manasseh == ManassehHome.book) {
      return ref;
    }

    return _translate(ref, (r) {
      final original = _eng.forward[r] ?? r;
      final prayer = _prayerFromCanonical(original, manasseh);
      if (prayer != null) {
        return prayer;
      }
      if (to == VerseScheme.eng) {
        return r;
      }

      return _tables[to]!.inverse[original] ?? original;
    });
  }

  // Место Молитвы Манассии в 2 Пар схемы [from] у перевода с домом молитвы
  // [home] — в книге MAN; `null` — [ref] не в молитве или карта его
  // не знает. Начало 2 Пар 37 (стих 0) — начало книги MAN.
  _SilRef? _prayerToCanonical(
    _SilRef ref,
    VerseScheme from,
    ManassehHome home,
  ) {
    final (code, chapter, verse) = ref;
    if (code != _VrsTable.chronicles) {
      return null;
    }
    final synodal = from == VerseScheme.rsc || from == VerseScheme.rso;
    final inRso = switch (chapter) {
      36
          when verse > _chronicles36Last &&
              (synodal || home == ManassehHome.chronicles36) =>
        (code, 37, verse - _chronicles36Last),
      37 when from == VerseScheme.rso || home == ManassehHome.chronicles37 =>
        ref,
      _ => null,
    };
    if (inRso == null) {
      return null;
    }

    return _rso.prayerForward[inRso] ??
        (inRso.$3 == 0 ? (_VrsTable.manasseh, 1, 0) : null);
  }

  // Место книги MAN в 2 Пар по дому молитвы [home]; `null` — дом
  // [ManassehHome.book], [original] не в книге MAN или карта его не знает.
  // Начало книги MAN (стих 0) — первый стих молитвы в 2 Пар 36 или начало
  // 2 Пар 37.
  _SilRef? _prayerFromCanonical(_SilRef original, ManassehHome home) {
    if (home == ManassehHome.book || original.$1 != _VrsTable.manasseh) {
      return null;
    }
    if (original case (_, 1, 0)) {
      return home == ManassehHome.chronicles36
          ? (_VrsTable.chronicles, 36, _chronicles36Last + 1)
          : (_VrsTable.chronicles, 37, 0);
    }
    final in37 = _rso.prayerInverse[original];
    if (in37 == null) {
      return null;
    }
    final (code, _, verse) = in37;

    return home == ManassehHome.chronicles36
        ? (code, 36, verse + _chronicles36Last)
        : in37;
  }

  /// Последний стих каждой главы книги в схеме: глава → стих.
  ///
  /// Книга без кода SIL или без строки в файле схемы — пустая карта.
  Map<int, int> lastVerses(VerseScheme scheme, int book) {
    final code = BookCatalog.byNumber(book)?.silCode;
    if (code == null) {
      return const {};
    }

    return Map.unmodifiable(_tables[scheme]!.lastVerses[code] ?? const {});
  }

  /// Распознаёт схему каждой книги модуля по последним стихам глав.
  ///
  /// [chapters] — книга → глава → последний стих, как в модуле. Очки схемы —
  /// число глав, где последний стих совпал со схемой; ничью разбивает
  /// [russianFlag]. [preferred] — схема традиции перевода (`lxx` у греческого,
  /// `vul` у латинского). Без неё `lxx` и `vul` не предлагаются вовсе: длины
  /// глав говорят о совпадении, а не о происхождении текста, и `vul` иначе
  /// брала бы 3 Царств у украинского перевода за одну главу 22:54. Названная
  /// схема выигрывает ничью первой, но только в книге, где её длины глав
  /// не те же, что у `eng`, — иначе греческий Новый Завет звался бы
  /// Септуагинтой. В Новом Завете `lxx` не предлагается вовсе: у Деяний
  /// и 2 Коринфянам её длины те же, что у `org`, а Септуагинта — Ветхий
  /// Завет. Книга без кода SIL в карту не попадает.
  BookSchemes detect(
    Map<int, Map<int, int>> chapters, {
    required bool russianFlag,
    VerseScheme? preferred,
  }) {
    final schemes = <int, VerseScheme>{};
    final uncertain = <int>{};
    for (final MapEntry(key: book, value: lasts) in chapters.entries) {
      if (BookCatalog.byNumber(book)?.silCode == null) {
        continue;
      }
      final order = _order(book, russianFlag, preferred);
      var best = order.first;
      var bestScore = -1;
      for (final scheme in order) {
        final score = _score(lasts, scheme, book);
        // Строго больше: при равных очках остаётся схема раньше по порядку.
        if (score > bestScore) {
          best = scheme;
          bestScore = score;
        }
      }
      schemes[book] = best;
      if (bestScore < lasts.length * 0.95) {
        uncertain.add(book);
      }
    }

    return BookSchemes(
      schemes: Map.unmodifiable(schemes),
      uncertain: Set.unmodifiable(uncertain),
    );
  }

  /// Сомнения в схемах [schemes] книг модуля с последними стихами глав
  /// [chapters]; [russianFlag] и [preferred] — как у [detect], книги
  /// [settled] (схема задана руками) не проверяются. Сомнительна книга, где:
  ///
  /// - схема совпала меньше чем на 95% глав ([SchemeDoubt.weak]), а у другой
  ///   схемы длины глав другие. Глава, чей последний стих меньше, чем у любой
  ///   схемы, — недопереведённая — не считается: о счёте она не говорит;
  /// - другая схема в главах, где её длины не те же, совпала хоть раз и не
  ///   реже ([SchemeDoubt.close]): выбор решил порядок схем, а не текст;
  /// - схема, которую [detect] этому переводу не предлагает (`lxx`, `vul`
  ///   без подсказки языка), совпала хотя бы на две главы больше
  ///   ([SchemeDoubt.better]): английский перевод Септуагинты или Вульгаты.
  ///   Её ставят руками. На одну главу — случайность: 3 Царств с 22:54 у
  ///   шведского и украинского переводов ложится в `vul` лучше всех.
  ///
  /// Синодальная схема у перевода не на русском сама по себе не сомнение:
  /// Откровение с 12:17, как у KJV, 1 Царств с 20:43, как у Лютера и
  /// Вульгаты, — по длинам глав это Синодальный счёт, и места он переводит
  /// верно.
  List<SchemeDoubt> doubts(
    Map<int, Map<int, int>> chapters,
    BookSchemes schemes, {
    required bool russianFlag,
    VerseScheme? preferred,
    Set<int> settled = const {},
  }) {
    final found = <SchemeDoubt>[];
    for (final MapEntry(key: book, value: lasts) in chapters.entries) {
      if (BookCatalog.byNumber(book)?.silCode == null ||
          settled.contains(book) ||
          lasts.isEmpty) {
        continue;
      }
      final scheme = schemes.of(book);
      final own = lastVerses(scheme, book);
      final matched = _score(lasts, scheme, book);
      VerseScheme? rival;
      var rivalMatched = -1;
      var close = false;
      for (final other in _order(book, russianFlag, preferred)) {
        final theirs = lastVerses(other, book);
        if (other == scheme || _sameLengths(theirs, own)) {
          continue;
        }
        // Главы книги, где у схем разные длины: сколько совпало с каждой.
        var ownWins = 0;
        var theirWins = 0;
        for (final MapEntry(key: c, value: v) in lasts.entries) {
          if (own[c] == theirs[c]) {
            continue;
          }
          if (v == own[c]) {
            ownWins++;
          } else if (v == theirs[c]) {
            theirWins++;
          }
        }
        final tie = theirWins > 0 && theirWins >= ownWins;
        final score = _score(lasts, other, book);
        if (tie && !close || (tie == close && score > rivalMatched)) {
          rival = other;
          rivalMatched = score;
          close = tie;
        }
      }
      final candidates = [scheme, ..._order(book, russianFlag, preferred)];
      var counted = 0;
      var countedMatched = 0;
      for (final MapEntry(key: c, value: v) in lasts.entries) {
        final ends = [for (final s in candidates) ?lastVerses(s, book)[c]];
        if (ends.isNotEmpty && ends.every((end) => v < end)) {
          continue;
        }
        counted++;
        if (own[c] == v) {
          countedMatched++;
        }
      }
      final weak = rival != null && countedMatched < counted * 0.95;
      final offered = {scheme, ..._order(book, russianFlag, preferred)};
      VerseScheme? better;
      var betterMatched = matched + 1;
      for (final other in VerseScheme.values) {
        final score = offered.contains(other) ? 0 : _score(lasts, other, book);
        if (score > betterMatched) {
          better = other;
          betterMatched = score;
        }
      }
      if (weak || close || better != null) {
        found.add(
          SchemeDoubt(
            book: book,
            scheme: scheme,
            matched: matched,
            chapters: lasts.length,
            rival: rival,
            rivalMatched: rival == null ? 0 : rivalMatched,
            weak: weak,
            close: close,
            better: better,
            betterMatched: better == null ? 0 : betterMatched,
          ),
        );
      }
    }
    found.sort((a, b) => a.book.compareTo(b.book));

    return found;
  }

  /// Подсказки [detect] по языку перевода (BCP 47): русский порядок схем
  /// у `ru`, `uk`, `be`, схема традиции — `lxx` у `grc`, `vul` у `la`.
  static ({bool russianFlag, VerseScheme? preferred}) hintsOf(String language) {
    final base = language.split('-').first;

    return (
      russianFlag: const {'ru', 'uk', 'be'}.contains(base),
      preferred: const {'grc': VerseScheme.lxx, 'la': VerseScheme.vul}[base],
    );
  }

  // Порядок схем-кандидатов книги [book].
  List<VerseScheme> _order(int book, bool russianFlag, VerseScheme? preferred) {
    final base = russianFlag ? _russianOrder : _otherOrder;

    return switch (preferred) {
      null => base,
      VerseScheme.lxx
          when BookCatalog.byNumber(book)?.testament ==
              Testament.newTestament =>
        base,
      final own when base.contains(own) => [
        own,
        ...base.where((s) => s != own),
      ],
      final own when _sameAsEng(own, book) => [...base, own],
      final own => [own, ...base],
    };
  }

  // Число глав [lasts], чей последний стих тот же, что у схемы.
  int _score(Map<int, int> lasts, VerseScheme scheme, int book) {
    final expected = lastVerses(scheme, book);

    return lasts.entries.where((e) => expected[e.key] == e.value).length;
  }

  static bool _sameLengths(Map<int, int> a, Map<int, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  bool _sameAsEng(VerseScheme scheme, int book) =>
      _sameLengths(lastVerses(scheme, book), lastVerses(VerseScheme.eng, book));

  /// Переводит место через таблицы SIL; книга без кода SIL — в себя.
  VerseRef _translate(VerseRef ref, _SilRef Function(_SilRef) map) {
    final code = BookCatalog.byNumber(ref.book)?.silCode;
    if (code == null) {
      return ref;
    }
    final source = (code, ref.chapter, ref.verse);
    final target = map(source);
    if (target == source) {
      return ref;
    }
    final (targetCode, chapter, verse) = target;
    final book = BookCatalog.bySilCode(targetCode)?.number;

    // Код SIL вне справочника книг: такого места у модуля нет.
    return book == null ? ref : VerseRef(book, chapter, verse);
  }
}

/// Разобранный файл `.vrs`.
final class _VrsTable {
  _VrsTable._(
    this.lastVerses,
    this.forward,
    this.inverse,
    this.prayerForward,
    this.prayerInverse,
  );

  factory _VrsTable.parse(String text) {
    final lastVerses = <String, Map<int, int>>{};
    final forward = <_SilRef, _SilRef>{};
    final inverse = <_SilRef, _SilRef>{};
    final prayerForward = <_SilRef, _SilRef>{};
    final prayerInverse = <_SilRef, _SilRef>{};
    for (final raw in text.split('\n')) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) {
        continue;
      }
      final sides = line.split('=');
      if (sides.length == 1) {
        _parseBook(line, raw, lastVerses);
        continue;
      }
      if (sides.length != 2) {
        throw FormatException('Строка .vrs с двумя «=»', raw);
      }
      final from = _parseSide(sides[0], raw);
      final to = _parseSide(sides[1], raw);
      if (from.first.$1 == chronicles && to.first.$1 == manasseh) {
        _pair(from, to, prayerForward, prayerInverse);
      } else if (!_skipped(from.first.$1, to.first.$1)) {
        _pair(from, to, forward, inverse);
      }
    }

    return _VrsTable._(
      lastVerses,
      forward,
      inverse,
      prayerForward,
      prayerInverse,
    );
  }

  /// Код SIL 2 Паралипоменон.
  static const chronicles = '2CH';

  /// Код SIL Молитвы Манассии.
  static const manasseh = 'MAN';

  // Книги, которых нет в справочнике.
  static const _foreignBooks = {'ESG', 'PS2', 'EZA'};

  // Справочник держит Молитву Манассии, Сусанну и Вила отдельными книгами.
  // Строки `2CH = MAN` идут в карту молитвы раньше этой проверки.
  static const _separateBooks = [
    {chronicles, manasseh},
    {'DAG', 'SUS'},
    {'DAG', 'BEL'},
  ];

  static final _chapterPattern = RegExp(r'^(\d+):(\d+)$');

  static final _sidePattern = RegExp(
    r'^([A-Z0-9]{3}) (\d+):(\d+)[a-z]?(?:-(\d+)[a-z]?)?$',
  );

  /// Последние стихи глав: код книги → глава → стих.
  final Map<String, Map<int, int>> lastVerses;

  /// Место схемы → еврейская нумерация.
  final Map<_SilRef, _SilRef> forward;

  /// Еврейская нумерация → место схемы.
  final Map<_SilRef, _SilRef> inverse;

  /// Карта молитвы: 2 Пар 37 → Молитва Манассии (строки `2CH = MAN`).
  final Map<_SilRef, _SilRef> prayerForward;

  /// Карта молитвы обратно: Молитва Манассии → 2 Пар 37.
  final Map<_SilRef, _SilRef> prayerInverse;

  // Пары [from] и [to] по индексу; лишние стихи длинной стороны идут
  // к последнему стиху короткой. Туда — первый стих, обратно — первый
  // источник, но источник со стихом 0 уступает источнику с ненулевым.
  static void _pair(
    List<_SilRef> from,
    List<_SilRef> to,
    Map<_SilRef, _SilRef> forward,
    Map<_SilRef, _SilRef> inverse,
  ) {
    final count = from.length > to.length ? from.length : to.length;
    for (var i = 0; i < count; i++) {
      final a = from[i < from.length ? i : from.length - 1];
      final b = to[i < to.length ? i : to.length - 1];
      forward.putIfAbsent(a, () => b);
      final known = inverse[b];
      if (known == null || (known.$3 == 0 && a.$3 != 0)) {
        inverse[b] = a;
      }
    }
  }

  // Пара — две разные книги: строки 2CH = 2CH остаются.
  static bool _skipped(String a, String b) =>
      _foreignBooks.contains(a) ||
      _foreignBooks.contains(b) ||
      a != b &&
          _separateBooks.any((pair) => pair.contains(a) && pair.contains(b));

  // Строка вида `GEN 1:31 2:25 …`.
  static void _parseBook(
    String line,
    String raw,
    Map<String, Map<int, int>> lastVerses,
  ) {
    final parts = line.split(RegExp(r'\s+'));
    final chapters = <int, int>{};
    for (final part in parts.skip(1)) {
      final match = _chapterPattern.firstMatch(part);
      if (match == null) {
        throw FormatException('Строка книги .vrs', raw);
      }
      chapters[int.parse(match[1]!)] = int.parse(match[2]!);
    }
    lastVerses.putIfAbsent(parts.first, () => {}).addAll(chapters);
  }

  // Сторона вида `PSA 9:22-39`; буквы частей стиха отбрасываются.
  static List<_SilRef> _parseSide(String side, String raw) {
    final match = _sidePattern.firstMatch(side.trim());
    if (match == null) {
      throw FormatException('Сторона соответствия .vrs', raw);
    }
    final book = match[1]!;
    final chapter = int.parse(match[2]!);
    final first = int.parse(match[3]!);
    final last = match[4] == null ? first : int.parse(match[4]!);
    if (last < first) {
      throw FormatException('Обратный диапазон стихов .vrs', raw);
    }

    return [for (var v = first; v <= last; v++) (book, chapter, v)];
  }
}
