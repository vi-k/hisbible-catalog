import 'dart:async';

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:http/http.dart' as http;

/// Откуда сборка берёт файлы по адресу.
abstract interface class Fetcher {
  /// Байты файла по адресу [uri].
  ///
  /// Файл не получен — исключение, например [FetchException].
  Future<List<int>> get(Uri uri);
}

/// Файл по адресу не получен: ответ сервера не 200.
final class FetchException implements Exception {
  /// Создаёт ошибку для адреса [uri] с кодом ответа [status].
  const FetchException(this.uri, this.status);

  /// Адрес файла.
  final Uri uri;

  /// Код ответа HTTP.
  final int status;

  @override
  String toString() => 'cannot fetch $uri: HTTP $status';
}

/// [Fetcher] по HTTP.
final class HttpFetcher implements Fetcher {
  /// Создаёт загрузчик; [client] — свой клиент HTTP, по умолчанию новый.
  /// Запрос вместе с телом ответа дольше [timeout] —
  /// [TimeoutException].
  HttpFetcher({http.Client? client, this.timeout = defaultTimeout})
    : _client = client ?? http.Client();

  /// Сколько по умолчанию ждать один файл.
  static const defaultTimeout = Duration(minutes: 2);

  /// Сколько ждать один файл вместе с телом ответа.
  final Duration timeout;

  final http.Client _client;

  /// Заголовок `User-Agent` запросов сборки.
  static const userAgent =
      'catalog_builder/$builderVersion '
      '(+https://github.com/vi-k/hisbible-catalog)';

  @override
  Future<List<int>> get(Uri uri) async {
    // `get` читает и тело ответа, так что предел покрывает весь файл.
    final response = await _client
        .get(uri, headers: const {'User-Agent': userAgent})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw FetchException(uri, response.statusCode);
    }

    return response.bodyBytes;
  }

  /// Закрывает клиент HTTP.
  void close() => _client.close();
}
