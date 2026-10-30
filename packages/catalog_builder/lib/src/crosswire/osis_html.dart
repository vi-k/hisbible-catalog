import 'package:catalog_builder/src/openbible/osis_books.dart';
import 'package:hisbible_format/hisbible_format.dart';

/// Коды книг, которыми ссылаются толкования CrossWire помимо кодов OSIS
/// [osisBooks]: сокращения старых модулей (так пишет ссылки Clarke).
const Map<String, String> crosswireBookAliases = {
  '1Jn': '1John',
  '1Thes': '1Thess',
  '2Jn': '2John',
  '2Thes': '2Thess',
  '3Jn': '3John',
  'Act': 'Acts',
  'Amo': 'Amos',
  'Deu': 'Deut',
  'Ecc': 'Eccl',
  'Est': 'Esth',
  'Exo': 'Exod',
  'Eze': 'Ezek',
  'Ezr': 'Ezra',
  'Jam': 'Jas',
  'Jde': 'Jude',
  'Jdg': 'Judg',
  'Joe': 'Joel',
  'Joh': 'John',
  'Jon': 'Jonah',
  'Jos': 'Josh',
  'Luk': 'Luke',
  'Mar': 'Mark',
  'Mat': 'Matt',
  'Oba': 'Obad',
  'Phi': 'Phil',
  'Plm': 'Phlm',
  'Pro': 'Prov',
  'Psa': 'Ps',
  'Rut': 'Ruth',
  'Sol': 'Song',
  'Tit': 'Titus',
  'Zac': 'Zech',
  'Zep': 'Zeph',
};

/// Номер книги справочника по коду OSIS или сокращению
/// [crosswireBookAliases]; незнакомый код — `null`.
int? crosswireBook(String code) =>
    osisBooks[code] ?? osisBooks[crosswireBookAliases[code]];

final _osisPlace = RegExp(r'^([1-3]?[A-Za-z]+)\.(\d{1,3})(?:\.(\d{1,3}))?$');

/// Место `osisRef` ссылки толкования: стих `Gen.1.1`, промежуток
/// `Gen.1.1-Gen.1.5` или глава `Gen.1` (от первого стиха до последнего
/// по нумерации `eng`); `null` — ссылку не прочесть.
///
/// Книга — код OSIS или сокращение [crosswireBookAliases]. Места нет
/// в нумерации `eng`, промежуток между книгами или перевёрнутый — `null`.
RefRange? parseOsisRef(String osisRef) {
  final parts = osisRef.trim().split('-');
  if (parts.isEmpty || parts.length > 2) {
    return null;
  }
  final first = _parsePlace(parts.first);
  final last = parts.length == 2 ? _parsePlace(parts.last) : first;
  if (first == null || last == null || first.book != last.book) {
    return null;
  }
  final lastVerses = Versification.standard.lastVerses(
    VerseScheme.eng,
    first.book,
  );
  final startVerse = first.verse ?? 1;
  final endVerse = last.verse ?? lastVerses[last.chapter];
  final startLast = lastVerses[first.chapter];
  final endLast = lastVerses[last.chapter];
  if (startLast == null ||
      endLast == null ||
      endVerse == null ||
      startVerse < 1 ||
      startVerse > startLast ||
      endVerse < 1 ||
      endVerse > endLast) {
    return null;
  }
  final start = VerseRef(first.book, first.chapter, startVerse);
  final end = VerseRef(last.book, last.chapter, endVerse);
  if (end.chapter < start.chapter ||
      (end.chapter == start.chapter && end.verse < start.verse)) {
    return null;
  }

  return end == start ? RefRange(start) : RefRange(start, end);
}

({int book, int chapter, int? verse})? _parsePlace(String text) {
  final match = _osisPlace.firstMatch(text);
  final book = match == null ? null : crosswireBook(match[1]!);
  if (match == null || book == null) {
    return null;
  }

  return (
    book: book,
    chapter: int.parse(match[2]!),
    verse: match[3] == null ? null : int.parse(match[3]!),
  );
}

/// Итог перевода записи OSIS в HTML.
final class OsisHtml {
  /// Создаёт итог.
  const OsisHtml(
    this.html, {
    required this.links,
    required this.unresolved,
    required this.notes,
  });

  /// HTML толкования; пустая строка — в записи нет текста.
  final String html;

  /// Ссылок `reference`, ставших `<a href="ref:…">`.
  final int links;

  /// Ссылок `reference` с `osisRef`, который не прочесть: остались текстом.
  final int unresolved;

  /// Сносок `note`.
  final int notes;
}

/// Переводит разметку OSIS толкования CrossWire в HTML.
///
/// Вехи `div type="x-p"` (`sID`/`eID`) — границы абзацев `<p>`, пустые
/// абзацы не пишутся; `title` — заголовки (`x-ms` — `<h3>`, `x-s` — `<h4>`,
/// `x-s2` — `<h5>`, `x-s3` — `<h6>`); `hi` bold и italic — `<b>` и `<i>`;
/// `reference` с прочитанным `osisRef` ([parseOsisRef]) — `<a href="ref:…">`,
/// с непрочитанным — текст; `note` — номер `<sup>` в тексте, сами сноски —
/// абзацами в конце; `table`/`row`/`cell` — `<table>`/`<tr>`/`<td>`;
/// `list`/`item` — `<ul>`/`<li>`; строки `lg`/`l` — через `<br>`. Прочие
/// вехи пропускаются, у незнакомого тега остаётся текст. Пробелы
/// схлопываются.
OsisHtml osisToHtml(String osis) => (_Converter()..run(osis)).result();

final _token = RegExp(
  r'<(/?)([A-Za-z][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'
  r"'[^']*'))*)\s*(/?)>",
);
final _attribute = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final _entity = RegExp(r'&(?:[A-Za-z][A-Za-z0-9]*|#\d+|#x[0-9A-Fa-f]+);');
final _spaces = RegExp(r'[ \t\r\n]+');
final _tags = RegExp('<[^>]*>');
final _spacedBreak = RegExp(' ?<br> ?');
final _leadingSpace = RegExp('^((?:<[a-z][^>]*>)+) ');
final _trailingSpace = RegExp(r' ((?:</[a-z0-9]+>)+)$');

const _headingTags = {'x-ms': 'h3', 'x-s': 'h4', 'x-s2': 'h5', 'x-s3': 'h6'};

// Строчный тег: открывающая и закрывающая строки HTML.
typedef _Tag = ({String open, String close});

// Строчный текст: абзац, заголовок, ячейка, пункт или сноска.
final class _Inline {
  final _buffer = StringBuffer();
  // Открытые и уже записанные теги.
  final _open = <_Tag>[];
  // Теги, открытые до прошлого абзаца: пишутся перед следующим текстом.
  final _pending = <_Tag>[];

  bool get isBlank => _isBlank(_buffer.toString());

  void text(String text) {
    if (text.isEmpty) {
      return;
    }
    if (text.trim().isNotEmpty) {
      _realize();
    }
    _buffer.write(text);
  }

  // Готовая разметка: номер сноски, `<br>`.
  void markup(String html) {
    _realize();
    _buffer.write(html);
  }

  void open(_Tag tag) {
    _realize();
    _buffer.write(tag.open);
    _open.add(tag);
  }

  void close(_Tag tag) {
    if (_pending.remove(tag)) {
      return;
    }
    final at = _open.lastIndexOf(tag);
    if (at < 0) {
      return;
    }
    final above = _open.sublist(at + 1);
    for (final inner in above.reversed) {
      _buffer.write(inner.close);
    }
    _buffer.write(tag.close);
    _open.removeRange(at, _open.length);
    above.forEach(open);
  }

  // Текст с закрытыми тегами; открытые теги перейдут в следующий текст.
  String take() {
    for (final tag in _open.reversed) {
      _buffer.write(tag.close);
    }
    final text = _buffer.toString();
    _buffer.clear();
    _pending.addAll(_open);
    _open.clear();

    return text;
  }

  void _realize() {
    if (_pending.isEmpty) {
      return;
    }
    final tags = List.of(_pending);
    _pending.clear();
    for (final tag in tags) {
      _buffer.write(tag.open);
      _open.add(tag);
    }
  }
}

bool _isBlank(String html) =>
    html.replaceAll(_tags, '').replaceAll(_spaces, '').isEmpty;

// Пробелы схлопнуты; у краёв текста, в том числе внутри крайних тегов,
// и вокруг `<br>` их нет.
String _normalize(String html) => html
    .replaceAll(_spaces, ' ')
    .trim()
    .replaceAll(_spacedBreak, '<br>')
    .replaceFirstMapped(_leadingSpace, (m) => m[1]!)
    .replaceFirstMapped(_trailingSpace, (m) => m[1]!);

// Чем был открытый элемент OSIS.
enum _Kind { inline, heading, note, cell, item, table, row, list, block, other }

// Открытый элемент: имя, вид, строчный тег и где он открыт.
final class _Open {
  _Open(this.name, this.kind, {this.tag, this.target, this.level});

  final String name;
  final _Kind kind;
  final _Tag? tag;
  final _Inline? target;
  final String? level;
}

final class _Converter {
  final _out = StringBuffer();
  final _paragraph = _Inline();
  // Текущий строчный текст: абзац или вложенный в него заголовок, ячейка,
  // пункт, сноска.
  final _targets = <_Inline>[];
  final _stack = <_Open>[];
  final _notes = <String>[];
  var _inNote = false;
  var _inHeading = false;
  var _containers = 0;
  var _links = 0;
  var _unresolved = 0;

  _Inline get _target => _targets.isEmpty ? _paragraph : _targets.last;

  OsisHtml result() {
    final html = StringBuffer()..write(_out);
    for (final (i, note) in _notes.indexed) {
      html.write('<p><sup>${i + 1}</sup> $note</p>');
    }

    return OsisHtml(
      html.toString(),
      links: _links,
      unresolved: _unresolved,
      notes: _notes.length,
    );
  }

  void run(String osis) {
    var at = 0;
    for (final match in _token.allMatches(osis)) {
      _text(osis.substring(at, match.start));
      at = match.end;
      final attributes = {
        for (final a in _attribute.allMatches(match[3]!)) a[1]!: a[2] ?? a[3]!,
      };
      final name = match[2]!;
      if (match[1]!.isNotEmpty) {
        _close(name);
      } else if (match[4]!.isNotEmpty) {
        _milestone(name, attributes);
      } else {
        _open(name, attributes);
      }
    }
    _text(osis.substring(at));
    while (_stack.isNotEmpty) {
      _end(_stack.removeLast());
    }
    _breakParagraph();
  }

  void _text(String raw) {
    if (raw.isEmpty) {
      return;
    }
    final text = raw
        .replaceAll('﻿', '')
        .replaceAll('<', '&lt;')
        .splitMapJoin(
          _entity,
          onMatch: (m) => m[0]!,
          onNonMatch: (s) => s.replaceAll('&', '&amp;'),
        );
    _target.text(text);
  }

  // Граница абзаца: в абзаце — новый абзац, во вложенном тексте — пробел.
  void _breakParagraph() {
    if (_targets.isNotEmpty) {
      _target.text(' ');

      return;
    }
    final html = _normalize(_paragraph.take());
    if (!_isBlank(html)) {
      _out.write('<p>$html</p>');
    }
  }

  void _milestone(String name, Map<String, String> attributes) {
    switch (name) {
      case 'div' when attributes['type'] == 'x-p':
      case 'p':
      case 'lg':
        _breakParagraph();
      case 'l' when attributes['eID'] == null:
      case 'lb':
        if (!_target.isBlank) {
          _target.markup('<br>');
        }
    }
  }

  void _open(String name, Map<String, String> attributes) {
    final type = attributes['type'];
    final nested = _inNote || _inHeading;
    switch (name) {
      case 'hi':
        final tag = switch (type) {
          'bold' => (open: '<b>', close: '</b>'),
          'italic' => (open: '<i>', close: '</i>'),
          _ => null,
        };
        _pushInline(name, tag);
      case 'reference':
        final osisRef = attributes['osisRef'];
        final range = osisRef == null ? null : parseOsisRef(osisRef);
        if (range != null) {
          _links++;
        } else if (osisRef != null) {
          _unresolved++;
        }
        _pushInline(
          name,
          range == null
              ? null
              : (open: '<a href="ref:${range.encode()}">', close: '</a>'),
        );
      case 'title' when !nested && _containers == 0:
        _breakParagraph();
        _inHeading = true;
        _targets.add(_Inline());
        _stack.add(
          _Open(name, _Kind.heading, level: _headingTags[type] ?? 'h4'),
        );
      case 'note' when !_inNote:
        _target.markup('<sup>${_notes.length + 1}</sup>');
        _notes.add('');
        _inNote = true;
        _targets.add(_Inline());
        _stack.add(_Open(name, _Kind.note));
      case 'table' when !nested && _containers == 0:
        _breakParagraph();
        _out.write('<table>');
        _stack.add(_Open(name, _Kind.table));
      case 'row' when _isOpen(_Kind.table):
        _out.write('<tr>');
        _stack.add(_Open(name, _Kind.row));
      case 'cell' when _isOpen(_Kind.row):
        _out.write('<td>');
        _containers++;
        _targets.add(_Inline());
        _stack.add(_Open(name, _Kind.cell));
      case 'list' when !nested && _containers == 0:
        _breakParagraph();
        _out.write('<ul>');
        _stack.add(_Open(name, _Kind.list));
      case 'item' when _isOpen(_Kind.list):
        _out.write('<li>');
        _containers++;
        _targets.add(_Inline());
        _stack.add(_Open(name, _Kind.item));
      case 'div' when type == 'x-p':
      case 'p':
      case 'lg':
        _breakParagraph();
        _stack.add(_Open(name, _Kind.block));
      case 'l':
        if (!_target.isBlank) {
          _target.markup('<br>');
        }
        _stack.add(_Open(name, _Kind.other));
      default:
        _stack.add(_Open(name, _Kind.other));
    }
  }

  bool _isOpen(_Kind kind) {
    for (final open in _stack.reversed) {
      if (open.kind == kind) {
        return true;
      }
      if (open.kind != _Kind.inline && open.kind != _Kind.other) {
        return false;
      }
    }

    return false;
  }

  void _pushInline(String name, _Tag? tag) {
    final target = _target;
    if (tag != null) {
      target.open(tag);
    }
    _stack.add(_Open(name, _Kind.inline, tag: tag, target: target));
  }

  void _close(String name) {
    final at = _stack.lastIndexWhere((open) => open.name == name);
    if (at < 0) {
      return;
    }
    while (_stack.length > at) {
      _end(_stack.removeLast());
    }
  }

  void _end(_Open open) {
    switch (open.kind) {
      case _Kind.inline:
        if (open.tag case final tag?) {
          open.target!.close(tag);
        }
      case _Kind.heading:
        _inHeading = false;
        final html = _normalize(_targets.removeLast().take());
        if (!_isBlank(html)) {
          _out.write('<${open.level}>$html</${open.level}>');
        }
      case _Kind.note:
        _inNote = false;
        _notes.last = _normalize(_targets.removeLast().take());
      case _Kind.cell:
        _containers--;
        _out.write('${_normalize(_targets.removeLast().take())}</td>');
      case _Kind.item:
        _containers--;
        _out.write('${_normalize(_targets.removeLast().take())}</li>');
      case _Kind.table:
        _out.write('</table>');
      case _Kind.row:
        _out.write('</tr>');
      case _Kind.list:
        _out.write('</ul>');
      case _Kind.block:
        _breakParagraph();
      case _Kind.other:
        break;
    }
  }
}
