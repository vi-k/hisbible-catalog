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
    // И 2 Коринфянам, где у `lxx` главы те же, что у `org`: в Новом Завете
    // Септуагинты нет.
    final corinthians = BookCatalog.numberOfCode('2CO')!;
    expect(
      vs
          .detect(
            {corinthians: of(VerseScheme.org, corinthians)},
            russianFlag: false,
            preferred: VerseScheme.lxx,
          )
          .of(corinthians),
      VerseScheme.org,
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

  group('doubts', () {
    BookSchemes schemesOf(Map<int, VerseScheme> s) => BookSchemes(schemes: s);
    final tobit = BookCatalog.numberOfCode('TOB')!;
    // Товит LXX без трёх последних стихов глав: ближе к синодальному счёту.
    final lxxTobit = {...of(VerseScheme.lxx, tobit), 5: 22, 10: 13, 11: 18};

    test('a weak match is a doubt', () {
      final d = vs
          .doubts(
            {tobit: lxxTobit},
            schemesOf({tobit: VerseScheme.rso}),
            russianFlag: false,
            preferred: VerseScheme.lxx,
          )
          .single;
      expect((d.scheme, d.matched, d.chapters), (VerseScheme.rso, 13, 14));
      expect((d.rival, d.rivalMatched), (VerseScheme.lxx, 11));
      expect((d.weak, d.close, d.better), (true, false, null));
    });

    test('a book set by hand is not checked', () {
      expect(
        vs.doubts(
          {tobit: lxxTobit},
          schemesOf({tobit: VerseScheme.lxx}),
          russianFlag: false,
          preferred: VerseScheme.lxx,
          settled: {tobit},
        ),
        isEmpty,
      );
    });

    test('a scheme chosen by order, not by text, is a doubt', () {
      // 3 Царств: в главах, где Синодальный и `org` расходятся, глава 4 —
      // по `org`, глава 5 — по Синодальному, глава 22 — ни по одной.
      final kings = {...of(VerseScheme.rsc, 110), 4: 20, 22: 50};
      final d = vs
          .doubts(
            {110: kings},
            schemesOf({110: VerseScheme.rsc}),
            russianFlag: true,
          )
          .single;
      expect((d.matched, d.rival, d.rivalMatched), (20, VerseScheme.org, 20));
      // Глава 22 короче, чем у любой схемы, и не считается: 20 из 21.
      expect((d.weak, d.close, d.better), (false, true, null));
    });

    test('a chapter translated in part says nothing', () {
      // Бытие: в главах 1 и 2 переведено по несколько стихов.
      final genesis = {...of(VerseScheme.eng, 10), 1: 5, 2: 3};
      expect(
        vs.doubts(
          {10: genesis},
          schemesOf({10: VerseScheme.eng}),
          russianFlag: false,
        ),
        isEmpty,
      );
    });

    test('a scheme offered only by the language is better', () {
      // Иеремия английского перевода Септуагинты: с `lxx` совпала целиком.
      final jeremiah = BookCatalog.numberOfCode('JER')!;
      final d = vs
          .doubts(
            {jeremiah: of(VerseScheme.lxx, jeremiah)},
            schemesOf({jeremiah: VerseScheme.org}),
            russianFlag: false,
          )
          .single;
      expect((d.better, d.betterMatched), (VerseScheme.lxx, 52));
    });

    test('one chapter more is no better', () {
      // 3 Царств с 22:54 и главами 4 и 5, как у `eng`: `vul` совпала
      // на одну главу больше.
      final kings = {...of(VerseScheme.eng, 110), 22: 54};
      expect(
        vs.doubts(
          {110: kings},
          schemesOf({110: VerseScheme.eng}),
          russianFlag: false,
        ),
        isEmpty,
      );
    });

    test('a Synodal scheme outside Russian is no doubt by itself', () {
      // Откровение с 12:17, как у KJV.
      final revelation = BookCatalog.numberOfCode('REV')!;
      expect(
        vs.doubts(
          {revelation: of(VerseScheme.rsc, revelation)},
          schemesOf({revelation: VerseScheme.rsc}),
          russianFlag: false,
        ),
        isEmpty,
      );
    });

    test('one telling chapter settles the scheme', () {
      // Деяния: `eng` и `org` расходятся только в главе 19, и она по `eng`.
      expect(
        vs.doubts(
          {510: of(VerseScheme.eng, 510)},
          schemesOf({510: VerseScheme.eng}),
          russianFlag: false,
        ),
        isEmpty,
      );
    });

    test('a clean book is no doubt', () {
      expect(
        vs.doubts(
          {520: of(VerseScheme.eng, 520)},
          schemesOf({520: VerseScheme.eng}),
          russianFlag: false,
        ),
        isEmpty,
      );
    });

    test('hints follow the language', () {
      expect(Versification.hintsOf('uk'), (russianFlag: true, preferred: null));
      expect(Versification.hintsOf('grc-x-lxx').preferred, VerseScheme.lxx);
      expect(Versification.hintsOf('la').preferred, VerseScheme.vul);
      expect(Versification.hintsOf('sr'), (
        russianFlag: false,
        preferred: null,
      ));
    });
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
      305: {1: 10},
    }, russianFlag: true);
    expect(m.of(305), VerseScheme.eng);
    expect(m.uncertain, isEmpty);
  });

  test('Additions to Esther are left out and map to themselves', () {
    // `ESG` бывает и всей греческой Есфирью, и главами 10–16 дополнений:
    // карте схемы книга не верит.
    final m = vs.detect({
      192: {10: 13, 11: 1, 16: 24},
    }, russianFlag: true);
    expect(m.of(192), VerseScheme.eng);
    expect(m.uncertain, isEmpty);
    expect(vs.lastVerses(VerseScheme.eng, 192), isEmpty);
    for (final scheme in VerseScheme.values) {
      expect(
        vs.toCanonical(const VerseRef(192, 13, 1), scheme),
        const VerseRef(192, 13, 1),
      );
    }
  });
}
