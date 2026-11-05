import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

void main() {
  test('licenses', () {
    expect(
      licenseOf('<a href="http://creativecommons.org/licenses/by-sa/4.0/">'),
      'CC-BY-SA-4.0',
    );
    expect(
      licenseOf('creativecommons.org/licenses/by-nc-nd/4.0'),
      'CC-BY-NC-ND-4.0',
    );
    expect(
      licenseOf('This is in the Public Domain.', copyright: 'Public Domain'),
      'PD',
    );
    expect(licenseOf(null), 'redistributable');
    expect(licenseOf(null, copyright: 'public domain'), 'redistributable');
  });

  test('any cc version keeps its number', () {
    expect(
      licenseOf('http://creativecommons.org/licenses/by-sa/3.0/'),
      'CC-BY-SA-3.0',
    );
    expect(
      licenseOf('https://creativecommons.org/licenses/by-nc/2.5/in/'),
      'CC-BY-NC-2.5',
    );
  });

  test('cc0 and the public domain mark are PD', () {
    expect(
      licenseOf(
        '<a href="https://creativecommons.org/publicdomain/zero/1.0/">CC0</a>',
      ),
      'PD',
    );
    expect(
      licenseOf('https://creativecommons.org/publicdomain/mark/1.0/'),
      'PD',
    );
  });

  test('a cc address wins over the words public domain', () {
    expect(
      licenseOf(
        'Not in the public domain. '
        'https://creativecommons.org/licenses/by/4.0/',
        copyright: 'public domain',
      ),
      'CC-BY-4.0',
    );
  });

  test('the words public domain need the Copyright column to agree', () {
    const page = 'This translation is in the public domain.';
    expect(licenseOf(page, copyright: 'Public Domain'), 'PD');
    expect(
      licenseOf(page, copyright: 'This translation is public domain.'),
      'PD',
    );
    expect(licenseOf(page), 'redistributable');
    expect(licenseOf(page, copyright: '© 2001 Someone'), 'redistributable');
    expect(
      licenseOf(page, copyright: 'Not public domain. © 2001 Someone'),
      'redistributable',
    );
    expect(
      licenseOf(
        '© 2001 Someone. All rights reserved.',
        copyright:
            'public '
            'domain',
      ),
      'redistributable',
    );
  });

  test('a negated public domain is not PD', () {
    const copyright = 'Public Domain';
    for (final page in [
      'This text is not in the public domain.',
      'NOT public domain; © 2001 Someone',
      'This is not a public domain work.',
      'It is no longer in the public domain.',
      "This translation isn't public domain.",
      'This translation isn’t in the public domain.',
    ]) {
      expect(licenseOf(page, copyright: copyright), 'redistributable');
    }
    expect(
      licenseOf(
        'Not in the public domain in the UK, public domain elsewhere.',
        copyright: copyright,
      ),
      'PD',
    );
  });

  test('a page without a license is redistributable', () {
    expect(
      licenseOf('<p>© 2001 Someone. All rights reserved.</p>'),
      'redistributable',
    );
  });

  test('reads name, language and public domain from an eBible page', () {
    const page = '''
<!DOCTYPE html>
<html lang="ru">
<head>
<title>Синодальный перевод  </title>
</head>
<body>
<h1 class='gentium_plus'>Синодальный перевод</h1>
<h2>Synodal Translation of the Holy Bible in Russian</h2>
<p><a href='http://en.wikipedia.org/wiki/Public_domain'>Public Domain</a><br />
Language: <a href='http://www.ethnologue.org/language/rus'>русский (Russian)</a><br />
</p>
<div class="copyright">
<p align="center"><a href='copyright.htm'>Public Domain</a></p>
</div>
</body></html>
''';

    expect(readCopyrightPage(page), (
      name: 'Синодальный перевод',
      language: 'ru',
      license: 'PD',
    ));
  });

  test('a page without h1 takes the title', () {
    final page = readCopyrightPage(
      '<html lang="en"><head><title> Some Bible </title></head> '
      '<body>© 2001 Someone</body></html>',
    );

    expect(page.name, 'Some Bible');
    expect(page.license, 'redistributable');
  });

  test('no lang gives null', () {
    final page = readCopyrightPage('<html><body><h1>Name</h1></body></html>');

    expect(page.language, isNull);
    expect(page.name, 'Name');
  });

  test('no h1 and no title give a null name', () {
    expect(readCopyrightPage('<p>text</p>').name, isNull);
  });

  test('entities in the name are decoded', () {
    final page = readCopyrightPage(
      '<h1>A &amp; B &lt;c&gt; &quot;d&quot; &#39;e&#39; &apos;f&apos;'
      ' &#1057;&#x421;&#X43F; &unknown; &#0; &#xD800;</h1>',
    );

    expect(page.name, 'A & B <c> "d" \'e\' \'f\' ССп &unknown; &#0; &#xD800;');
  });

  test('a non-breaking space becomes a plain one', () {
    expect(readCopyrightPage('<h1>A&nbsp;&nbsp;B</h1>').name, 'A B');
  });

  test('a multi-line h1 with inner tags is one line', () {
    final page = readCopyrightPage(
      '<h1 class="x">\n  Holy\n  <span>Bible</span>\tof\r\n  Rus</h1>',
    );

    expect(page.name, 'Holy Bible of Rus');
  });

  test('direction controls are removed from the name', () {
    final page = readCopyrightPage(
      '<h1>\u200E\u202B שלום \u200F\u2066עולם\u2069\u202C </h1>',
    );

    expect(page.name, 'שלום עולם');
  });
}
