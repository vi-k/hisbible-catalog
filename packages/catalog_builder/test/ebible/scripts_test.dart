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
    expect(scriptCodeOf('Khmer', 'ព្រះគម្ពីរ 123'), 'Zyyy');
    expect(scriptCodeOf('Khmer', ''), 'Zyyy');
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

  test('only the first 10000 letters count', () {
    final sample = '${'ж' * 10000}${'w' * 20000}';
    expect(scriptCodeOf('Unknown', sample), 'Cyrl');
  });
}
