/// Текст без BOM (`U+FEFF`) в начале.
String withoutBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;

/// Дата [date] в виде `YYYY-MM-DD`.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
