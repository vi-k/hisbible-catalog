/// Формат модулей HisBible: книги, нумерация стихов, разметка и файл модуля.
library;

export 'src/books/book_catalog.dart';
export 'src/books/book_info.dart';
export 'src/markup/markup_node.dart';
export 'src/markup/markup_parser.dart';
export 'src/markup/markup_writer.dart';
export 'src/markup/plain_text.dart';
export 'src/module/bible_module.dart';
export 'src/module/commentary_module.dart';
export 'src/module/crossref_module.dart';
export 'src/module/module_check.dart' show checkModuleFile, readModuleMeta;
export 'src/module/module_meta.dart';
export 'src/module/module_version.dart';
export 'src/module/module_writer.dart';
export 'src/module/schema.dart'
    show
        BookKind,
        FootnoteKind,
        HeadingKind,
        WritingDirection,
        formatApplicationId,
        formatVersion,
        maxChapterNumber,
        maxVerseEndSpan,
        maxVerseNumber;
export 'src/module_type.dart';
export 'src/problems.dart';
export 'src/refs/verse_ref.dart';
export 'src/versification/book_schemes.dart';
export 'src/versification/versification.dart';
