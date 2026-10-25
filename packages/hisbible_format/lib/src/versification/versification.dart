import 'package:hisbible_format/src/books/book_catalog.dart';
import 'package:hisbible_format/src/refs/verse_ref.dart';
import 'package:hisbible_format/src/versification/book_schemes.dart';
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

  /// Четыре схемы SIL из `vrs_data.dart`; разбираются при первом обращении.
  static final Versification standard = Versification.fromVrs({
    VerseScheme.eng: engVrs,
    VerseScheme.org: orgVrs,
    VerseScheme.rso: rsoVrs,
    VerseScheme.rsc: rscVrs,
  });

  // Порядок схем при ничьей в распознавании.
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

  final Map<VerseScheme, _VrsTable> _tables;

  _VrsTable get _eng => _tables[VerseScheme.eng]!;

  /// Переводит место [ref] из схемы [from] в каноническую.
  VerseRef toCanonical(VerseRef ref, VerseScheme from) {
    if (from == VerseScheme.eng) {
      return ref;
    }

    return _translate(ref, (r) {
      final original = _tables[from]!.forward[r] ?? r;

      return _eng.inverse[original] ?? original;
    });
  }

  /// Переводит каноническое место [ref] в схему [to].
  VerseRef fromCanonical(VerseRef ref, VerseScheme to) {
    if (to == VerseScheme.eng) {
      return ref;
    }

    return _translate(ref, (r) {
      final original = _eng.forward[r] ?? r;

      return _tables[to]!.inverse[original] ?? original;
    });
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
  /// [russianFlag]. Книга без кода SIL в карту не попадает.
  BookSchemes detect(
    Map<int, Map<int, int>> chapters, {
    required bool russianFlag,
  }) {
    final order = russianFlag ? _russianOrder : _otherOrder;
    final schemes = <int, VerseScheme>{};
    final uncertain = <int>{};
    for (final MapEntry(key: book, value: lasts) in chapters.entries) {
      if (BookCatalog.byNumber(book)?.silCode == null) {
        continue;
      }
      var best = order.first;
      var bestScore = -1;
      for (final scheme in order) {
        final expected = lastVerses(scheme, book);
        final score = lasts.entries
            .where((e) => expected[e.key] == e.value)
            .length;
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
  _VrsTable._(this.lastVerses, this.forward, this.inverse);

  factory _VrsTable.parse(String text) {
    final lastVerses = <String, Map<int, int>>{};
    final forward = <_SilRef, _SilRef>{};
    final inverse = <_SilRef, _SilRef>{};
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
      if (_skipped(from.first.$1, to.first.$1)) {
        continue;
      }
      // Пары по индексу; лишние стихи длинной стороны идут к последнему
      // стиху короткой.
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

    return _VrsTable._(lastVerses, forward, inverse);
  }

  // Книги, которых нет в справочнике.
  static const _foreignBooks = {'ESG', 'PS2', 'EZA'};

  // Справочник держит Молитву Манассии, Сусанну и Вила отдельными книгами.
  static const _separateBooks = [
    {'2CH', 'MAN'},
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
