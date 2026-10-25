import 'package:catalog_builder/catalog_builder.dart';
import 'package:test/test.dart';

void main() {
  test('scripts', () {
    expect(scriptCodeOf('Latin', ''), 'Latn');
    expect(scriptCodeOf('Code for uncoded script', 'ሰላም ለዓለም'), 'Ethi');
  });

  test('csv script names', () {
    expect(
      scriptCodeOf('Latin (Roman) with Papua New Guinea enhancements', ''),
      'Latn',
    );
    expect(scriptCodeOf('Cyrillic', ''), 'Cyrl');
    expect(scriptCodeOf('Devanagari (Nagari)', ''), 'Deva');
    expect(scriptCodeOf('Ethiopic (Geʻez)', ''), 'Ethi');
    expect(scriptCodeOf('Amheric', ''), 'Ethi');
    expect(scriptCodeOf('CJK', ''), 'Hani');
    expect(scriptCodeOf('Han (Simplified variant)', ''), 'Hans');
    expect(scriptCodeOf('Burmese', ''), 'Mymr');
    expect(scriptCodeOf('Tifenagh', ''), 'Tfng');
  });

  test('another name goes by the letters of the sample', () {
    expect(scriptCodeOf('Hindi', 'नमस्ते दुनिया, hi'), 'Deva');
    expect(scriptCodeOf('Han (Traditional Variant)', '太初有道。'), 'Hani');
    expect(scriptCodeOf('', 'В начале было Слово (Logos)'), 'Cyrl');
    expect(scriptCodeOf('Unknown', '123 ; 456'), 'Zyyy');
    expect(scriptCodeOf('Unknown', ''), 'Zyyy');
  });

  test('the text wins over the column', () {
    expect(
      scriptCodeOf('Latin', 'В начале сотворил Бог небо и землю.'),
      'Cyrl',
    );
    expect(scriptCodeOf('Latin', 'Ἐν ἀρχῇ ἦν ὁ λόγος'), 'Grek');
    expect(scriptCodeOf('Latin', 'Սկզբում Աստված ստեղծեց'), 'Armn');
    expect(scriptCodeOf('Latin', 'დასაბამად შექმნა ღმერთმა'), 'Geor');
    expect(scriptCodeOf('Latin', '태초에 하나님이 천지를'), 'Hang');
    expect(scriptCodeOf('Cyrillic', 'In the beginning'), 'Latn');
  });

  test('the column tells simplified han apart', () {
    expect(scriptCodeOf('Han (Simplified variant)', '起初神创造天地。'), 'Hans');
    expect(scriptCodeOf('CJK', '起初神創造天地。'), 'Hani');
    expect(scriptCodeOf('Han (Simplified variant)', 'Genesis'), 'Latn');
  });

  test('digits and signs inside a range are not letters', () {
    expect(scriptCodeOf('', '١٢٣٤٥٦٧٨٩٠ ١٢٣٤٥٦٧٨٩٠ ، ؟ Psalm'), 'Latn');
    expect(scriptCodeOf('', '१२३४५६७८९० । Word'), 'Latn');
  });

  test('coptic in greek letters stays coptic', () {
    expect(scriptCodeOf('Coptic', 'ⲁⲣⲭⲏ Ϩⲉⲛ'), 'Copt');
    expect(scriptCodeOf('Coptic', 'Ϧⲉⲛ ⲟⲩⲁⲣⲭⲏ'), 'Copt');
    expect(scriptCodeOf('Coptic', 'Ἐν ἀρχῇ ἦν ὁ λόγος'), 'Copt');
    expect(scriptCodeOf('Latin', 'Ἐν ἀρχῇ ἦν ὁ λόγος'), 'Grek');
  });

  test('more scripts by letters', () {
    expect(scriptCodeOf('Code for uncoded script', 'ព្រះគម្ពីរ 123'), 'Khmr');
    expect(scriptCodeOf('Latin', 'ආරම්භයේදී දෙවියන් වහන්සේ'), 'Sinh');
    expect(scriptCodeOf('Latin', 'ພຣະຄຳພີ'), 'Laoo');
    expect(scriptCodeOf('Latin', 'ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ'), 'Mong');
    expect(scriptCodeOf('Latin', 'ᏣᎳᎩ ᎦᏬᏂᎯᏍᏗ'), 'Cher');
    expect(scriptCodeOf('Latin', 'ᐃᓄᒃᑎᑐᑦ'), 'Cans');
    expect(scriptCodeOf('Latin', 'ꆈꌠꁱꂷ'), 'Yiii');
    expect(scriptCodeOf('Latin', 'ꕙꔤ ꔞꘋ'), 'Vaii');
    expect(scriptCodeOf('Latin', 'ދިވެހި ބަސް'), 'Thaa');
    expect(scriptCodeOf('Latin', 'ꦧꦱꦗꦮ'), 'Java');
    expect(scriptCodeOf('Latin', 'ᬩᬲᬩᬮᬶ'), 'Bali');
    expect(scriptCodeOf('Latin', 'ꤊꤢꤛꤢ'), 'Kali');
    expect(scriptCodeOf('Latin', 'ꠍꠤꠟꠐꠤ'), 'Sylo');
  });

  test('more csv script names', () {
    expect(scriptCodeOf('Khmer', ''), 'Khmr');
    expect(scriptCodeOf('Lao', ''), 'Laoo');
    expect(scriptCodeOf('Thaana', ''), 'Thaa');
    expect(scriptCodeOf('Unified Canadian Aboriginal Syllabics', ''), 'Cans');
    expect(scriptCodeOf('Kayah Li', ''), 'Kali');
    expect(scriptCodeOf('Syloti Nagri', ''), 'Sylo');
    expect(scriptCodeOf('Tifinagh', ''), 'Tfng');
  });

  test('kana makes han text japanese', () {
    expect(scriptCodeOf('CJK', '初めに、神は天と地を創造された。'), 'Jpan');
    expect(scriptCodeOf('Latin', 'これはペンです, a pen'), 'Jpan');
    // Каны 5 % от иероглифов с каной — уже японский, меньше — ещё нет.
    expect(scriptCodeOf('CJK', '${'の' * 5}${'神' * 95}'), 'Jpan');
    expect(scriptCodeOf('CJK', '${'の' * 4}${'神' * 96}'), 'Hani');
  });

  test('common characters tell simplified and traditional han', () {
    expect(scriptCodeOf('CJK', '神说：要有光，就有了光。'), 'Hans');
    expect(scriptCodeOf('CJK', '神說：要有光，就有了光。'), 'Hant');
    expect(scriptCodeOf('CJK', '耶稣对他们说：我就是道路。'), 'Hans');
    expect(scriptCodeOf('CJK', '耶穌對他們說：我就是道路。'), 'Hant');
    // Текст важнее столбца.
    expect(scriptCodeOf('Han (Simplified variant)', '神說：要有光。'), 'Hant');
    // Решает большинство.
    expect(scriptCodeOf('CJK', '這说说'), 'Hans');
    expect(scriptCodeOf('CJK', '这說說'), 'Hant');
    // Ни одной пары — столбец или `Hani`.
    expect(scriptCodeOf('Han (Simplified variant)', '太初有道。'), 'Hans');
    expect(scriptCodeOf('Han (Traditional Variant)', '太初有道。'), 'Hani');
  });

  test('only the first 10000 letters count', () {
    final sample = '${'ж' * 10000}${'w' * 20000}';
    expect(scriptCodeOf('Unknown', sample), 'Cyrl');
  });
}
