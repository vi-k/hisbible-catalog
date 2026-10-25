// Строки CSV склеиваются из кусков без пробелов между полями.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:catalog_builder/catalog_builder.dart';
import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('languages', () {
    expect(bcp47Of('rus'), 'ru');
    expect(bcp47Of('eng'), 'en');
    expect(bcp47Of('cmn'), 'zh');
    expect(bcp47Of('arb'), 'ar');
    expect(bcp47Of('grc'), 'grc');
  });

  test('a code without a short tag stays, an empty one is und', () {
    expect(bcp47Of('pes'), 'fa');
    expect(bcp47Of('qaa'), 'qaa');
    expect(bcp47Of('cnr'), 'cnr');
    expect(bcp47Of(' '), 'und');
  });

  test('parses translations csv', () {
    const csv =
        '\uFEFF"languageCode","translationId","languageName",'
        '"languageNameInEnglish","dialect","title","description",'
        '"Redistributable","Copyright","UpdateDate","publicationURL",'
        '"OTverses","NTverses","DCverses","textDirection","downloadable",'
        '"shortTitle","script"\r\n'
        '"heb","heb-test","עברית","Hebrew","","Test, the ""Best"" Bible",'
        '"Line one\nline two","True","© 2001, Someone","2026-09-26",'
        '"http://ebible.org/heb-test/","23145","7957","","rtl","False",'
        '"Test","Hebrew"\r\n'
        'rus,russyn,русский,Russian,,Синодальный перевод,,False,,2022-11-25,'
        ',23214,7955,0,ltr,True,,Cyrillic\n';
    final [heb, rus] = parseTranslationsCsv(csv);

    expect(heb.languageCode, 'heb');
    expect(heb.translationId, 'heb-test');
    expect(heb.languageName, 'עברית');
    expect(heb.languageNameInEnglish, 'Hebrew');
    expect(heb.title, 'Test, the "Best" Bible');
    expect(heb.description, 'Line one\nline two');
    expect(heb.redistributable, isTrue);
    expect(heb.copyright, '© 2001, Someone');
    expect(heb.updateDate, '2026-09-26');
    expect(heb.publicationUrl, 'http://ebible.org/heb-test/');
    expect((heb.otVerses, heb.ntVerses, heb.dcVerses), (23145, 7957, 0));
    expect(heb.textDirection, WritingDirection.rtl);
    expect(heb.downloadable, isFalse);
    expect(heb.shortTitle, 'Test');
    expect(heb.script, 'Hebrew');

    expect(rus.translationId, 'russyn');
    expect(rus.title, 'Синодальный перевод');
    expect(rus.redistributable, isFalse);
    expect((rus.otVerses, rus.ntVerses, rus.dcVerses), (23214, 7955, 0));
    expect(rus.textDirection, WritingDirection.ltr);
    expect(rus.downloadable, isTrue);
    expect(rus.script, 'Cyrillic');
  });

  test('a csv without translationId is not a translations table', () {
    expect(
      () => parseTranslationsCsv('a,b\n1,2\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
