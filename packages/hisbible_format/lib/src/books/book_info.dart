/// Раздел Писания, к которому относится книга.
///
/// Неканонические книги разнесены по разделам по русской традиции.
enum BookSection {
  /// Пятикнижие.
  pentateuch,

  /// Исторические книги.
  historical,

  /// Учительные книги.
  poetic,

  /// Пророки: большие и малые.
  prophets,

  /// Евангелия.
  gospels,

  /// Деяния апостолов.
  acts,

  /// Послания: соборные и Павловы.
  epistles,

  /// Откровение.
  revelation,
}

/// Завет, в который входит книга.
enum Testament {
  /// Ветхий Завет.
  old,

  /// Новый Завет.
  newTestament,
}

/// Описание книги из справочника книг.
final class BookInfo {
  /// Создаёт описание книги.
  const BookInfo({
    required this.number,
    required this.color,
    required this.section,
    required this.deuterocanonical,
    required this.ruShort,
    required this.ruLong,
    required this.enShort,
    required this.enLong,
    this.silCode,
  });

  /// Номер книги справочника.
  final int number;

  /// Цвет книги в виде `0xRRGGBB`.
  final int color;

  /// Раздел, в который входит книга.
  final BookSection section;

  /// Неканоническая ли книга.
  final bool deuterocanonical;

  /// Короткое русское название.
  final String ruShort;

  /// Полное русское название.
  final String ruLong;

  /// Короткое английское название.
  final String enShort;

  /// Полное английское название.
  final String enLong;

  /// Трёхсимвольный код SIL; у части неканонических книг его нет.
  final String? silCode;

  /// Завет книги: ветхий — до `prophets` включительно.
  Testament get testament => section.index <= BookSection.prophets.index
      ? Testament.old
      : Testament.newTestament;
}
