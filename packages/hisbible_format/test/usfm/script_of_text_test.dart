import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('Cyrillic text is Cyrl', () {
    expect(scriptOfText('В начале было Слово'), 'Cyrl');
  });

  test('Ethiopic text is Ethi', () {
    expect(scriptOfText('ሰላም ለዓለም'), 'Ethi');
  });

  test('Hebrew text is Hebr', () {
    expect(scriptOfText('בראשית ברא אלהים'), 'Hebr');
  });

  test('digits and punctuation give null', () {
    expect(scriptOfText('123 ; 456'), isNull);
    expect(scriptOfText(''), isNull);
  });
}
