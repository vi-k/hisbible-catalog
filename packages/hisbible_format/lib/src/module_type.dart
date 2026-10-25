/// Тип модуля HisBible.
enum ModuleType {
  /// Перевод Библии: `Имя.hb`.
  bible,

  /// Толкования и сноски: `Имя.commentaries.hb`.
  commentaries,

  /// Перекрёстные ссылки: `Имя.crossreferences.hb`.
  crossReferences,
}

/// Расширение файла модуля.
const String moduleExtension = '.hb';

/// Имя файла модуля с сокращением [abbreviation] и типом [type].
///
/// Например, `NRT'23.hb`, `Лопухин.commentaries.hb`, `OB.crossreferences.hb`.
String moduleFileName(String abbreviation, ModuleType type) {
  final infix = switch (type) {
    ModuleType.bible => '',
    ModuleType.commentaries => '.commentaries',
    ModuleType.crossReferences => '.crossreferences',
  };

  return '$abbreviation$infix$moduleExtension';
}
