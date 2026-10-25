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
  HttpFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Заголовок `User-Agent` запросов сборки.
  static const userAgent =
      'catalog_builder/$builderVersion '
      '(+https://github.com/vi-k/hisbible-catalog)';

  @override
  Future<List<int>> get(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const {'User-Agent': userAgent},
    );
    if (response.statusCode != 200) {
      throw FetchException(uri, response.statusCode);
    }

    return response.bodyBytes;
  }

  /// Закрывает клиент HTTP.
  void close() => _client.close();
}
