import 'package:hisbible_format/hisbible_format.dart';
import 'package:test/test.dart';

final vs = Versification.standard;

Map<int, int> of(VerseScheme s, int book) => vs.lastVerses(s, book);

void main() {
  test('detects the scheme of each book', () {
    // LUT+, BT'03, CRA: Псалтирь по еврейскому тексту, флаг false
    var m = vs.detect({
      230: of(VerseScheme.org, 230),
      520: of(VerseScheme.eng, 520),
    }, russianFlag: false);
    expect((m.of(230), m.of(520)), (VerseScheme.org, VerseScheme.eng));
    expect(m.uncertain, isEmpty);
    // NRT'23: русская Псалтирь, но Римлянам английское
    m = vs.detect({
      230: of(VerseScheme.rsc, 230),
      520: of(VerseScheme.eng, 520),
    }, russianFlag: true);
    expect((m.of(230), m.of(520)), (VerseScheme.rsc, VerseScheme.eng));
    expect(m.of(470), VerseScheme.eng);
  });

  test('ties follow the flag', () {
    // RST77: 114:9 как у rsc и Пс 151 как у rso — ничья, флаг true
    final psalms = {...of(VerseScheme.rsc, 230), 151: 7};
    expect(
      vs.detect({230: psalms}, russianFlag: true).of(230),
      VerseScheme.rsc,
    );
    // Авдий: одна глава одинаковая во всех схемах
    expect(
      vs.detect({380: of(VerseScheme.eng, 380)}, russianFlag: false).of(380),
      VerseScheme.eng,
    );
    expect(
      vs.detect({380: of(VerseScheme.eng, 380)}, russianFlag: true).of(380),
      VerseScheme.rsc,
    );
    // Откровение с нумерацией KJV: в главе 12 нет стиха 18, как у rsc
    expect(
      vs
          .detect({
            730: {...of(VerseScheme.eng, 730), 12: 17},
          }, russianFlag: false)
          .of(730),
      VerseScheme.rsc,
    );
  });

  test('the scheme of the tradition wins a tie', () {
    // Псалтирь LXX: длины глав те же, что у Синодального.
    final psalms = {230: of(VerseScheme.lxx, 230)};
    expect(
      vs.detect(psalms, russianFlag: false, preferred: VerseScheme.lxx).of(230),
      VerseScheme.lxx,
    );
    // Греческий Новый Завет остаётся `eng`: у `lxx` там те же главы.
    expect(
      vs
          .detect(
            {520: of(VerseScheme.eng, 520)},
            russianFlag: false,
            preferred: VerseScheme.lxx,
          )
          .of(520),
      VerseScheme.eng,
    );
    // Без подсказки схемы традиции не предлагаются: 3 Царств с 22:54
    // у украинского перевода — Синодальный с одной главой мимо, а не Вульгата.
    final kings = {...of(VerseScheme.rsc, 110), 22: 54};
    expect(vs.detect({110: kings}, russianFlag: true).of(110), VerseScheme.rsc);
    expect(
      vs
          .detect({110: kings}, russianFlag: true, preferred: VerseScheme.vul)
          .of(110),
      VerseScheme.vul,
    );
  });

  test('a book matching no scheme is uncertain', () {
    final garbled = {
      for (final e in of(VerseScheme.eng, 230).entries)
        e.key: e.key < 80 ? e.value + 3 : e.value,
    };
    final m = vs.detect({230: garbled}, russianFlag: false);
    // Запись с множеством matcher сравнил бы по ==, то есть по тождеству
    // множеств, поэтому проверки раздельные.
    expect(m.of(230), VerseScheme.eng);
    expect(m.uncertain, {230});
  });

  test('a book without SIL code is left out', () {
    final m = vs.detect({
      192: {1: 10},
    }, russianFlag: true);
    expect(m.of(192), VerseScheme.eng);
    expect(m.uncertain, isEmpty);
  });
}
