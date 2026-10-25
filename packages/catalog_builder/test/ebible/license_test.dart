import 'package:catalog_builder/catalog_builder.dart';
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
    expect(licenseOf('This is in the Public Domain.'), 'PD');
    expect(licenseOf(null), 'redistributable');
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
      ),
      'CC-BY-4.0',
    );
  });

  test('a negated public domain is not PD', () {
    expect(
      licenseOf('This text is not in the public domain.'),
      'redistributable',
    );
    expect(licenseOf('NOT public domain; © 2001 Someone'), 'redistributable');
    expect(
      licenseOf('Not in the public domain in the UK, public domain elsewhere.'),
      'PD',
    );
  });

  test('a page without a license is redistributable', () {
    expect(
      licenseOf('<p>© 2001 Someone. All rights reserved.</p>'),
      'redistributable',
    );
  });
}
