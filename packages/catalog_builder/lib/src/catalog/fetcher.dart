import 'dart:async';
import 'dart:io' show HttpDate, HttpException;

import 'package:catalog_builder/src/build/module_build.dart';
import 'package:http/http.dart' as http;

/// Откуда сборка берёт файлы по адресу.
abstract interface class Fetcher {
  /// Байты файла по адресу [uri].
  ///
  /// Файл не получен — исключение, например [FetchException].
  Future<List<int>> get(Uri uri);
}

/// Файл с заголовком `Last-Modified` ответа.
final class FetchedFile {
  /// Создаёт файл из [bytes]; [lastModified] — `Last-Modified` ответа
  /// (UTC) или `null`, если сервер его не прислал.
  const FetchedFile(this.bytes, {this.lastModified});

  /// Байты файла.
  final List<int> bytes;

  /// Когда файл менялся по словам сервера; `null` — заголовка нет.
  final DateTime? lastModified;
}

/// [Fetcher], который отдаёт ещё и заголовки ответа.
abstract interface class HeaderFetcher implements Fetcher {
  /// Файл по адресу [uri] с его `Last-Modified`.
  ///
  /// Файл не получен — исключение, например [FetchException].
  Future<FetchedFile> getFile(Uri uri);
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
final class HttpFetcher implements HeaderFetcher {
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
  Future<List<int>> get(Uri uri) async => (await getFile(uri)).bytes;

  @override
  Future<FetchedFile> getFile(Uri uri) async {
    // `get` читает и тело ответа, так что предел покрывает весь файл.
    final response = await _client
        .get(uri, headers: const {'User-Agent': userAgent})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw FetchException(uri, response.statusCode);
    }

    // Нечитаемая дата — то же, что отсутствующая.
    final header = response.headers['last-modified'];
    DateTime? lastModified;
    if (header != null) {
      try {
        lastModified = HttpDate.parse(header).toUtc();
      } on HttpException {
        lastModified = null;
      }
    }

    return FetchedFile(response.bodyBytes, lastModified: lastModified);
  }

  /// Закрывает клиент HTTP.
  void close() => _client.close();
}
