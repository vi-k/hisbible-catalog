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

  test('only the first 10000 letters count', () {
    final sample = '${'ж' * 10000}${'w' * 20000}';
    expect(scriptCodeOf('Unknown', sample), 'Cyrl');
  });
}
