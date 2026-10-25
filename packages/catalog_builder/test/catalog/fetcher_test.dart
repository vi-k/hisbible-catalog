import 'dart:async';

import 'package:catalog_builder/catalog_builder.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('https://ebible.org/Scriptures/aaa_usfm.zip');

  test('gets the bytes with the builder User-Agent', () async {
    late http.Request seen;
    final fetcher = HttpFetcher(
      client: MockClient((request) async {
        seen = request;

        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    expect(await fetcher.get(uri), [1, 2, 3]);
    expect(seen.url, uri);
    expect(seen.headers['User-Agent'], HttpFetcher.userAgent);
  });

  test('another status is a FetchException', () async {
    final fetcher = HttpFetcher(
      client: MockClient((_) async => http.Response('gone', 404)),
    );

    await expectLater(
      fetcher.get(uri),
      throwsA(
        isA<FetchException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.uri, 'uri', uri),
      ),
    );
  });

  test('a request that takes too long times out', () async {
    final fetcher = HttpFetcher(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));

        return http.Response('late', 200);
      }),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(fetcher.get(uri), throwsA(isA<TimeoutException>()));
  });

  test('the default timeout is two minutes', () {
    expect(HttpFetcher.defaultTimeout, const Duration(minutes: 2));
  });
}
