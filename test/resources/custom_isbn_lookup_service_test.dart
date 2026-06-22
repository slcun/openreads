import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/resources/custom_isbn_lookup_service.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';

void main() {
  const isbn = '9780306406157';

  group('CustomIsbnLookupService', () {
    test('sends a GET request and maps a result', () async {
      final client = _RecordingClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://books.example/$isbn?key=secret');
        expect(request.headers['x-token'], 'secret');
        return http.Response(
          '{"book":{"title":"Dune","author":"Frank Herbert",'
          '"isbn":"9780441172719","pages":412,"year":"1965",'
          '"cover":"https://covers.example/dune.jpg","publisher":"Ace",'
          '"description":"A novel","id":"dune-1"}}',
          200,
        );
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore('secret'),
      ).lookup(isbn: isbn, sources: [_source()]);

      expect(result, isNotNull);
      expect(result!.title, 'Dune');
      expect(result.author, 'Frank Herbert');
      expect(result.isbn, '9780441172719');
      expect(result.pageCount, 412);
      expect(result.publicationYear, 1965);
      expect(result.coverUrl, 'https://covers.example/dune.jpg');
      expect(result.publisher, 'Ace');
      expect(result.description, 'A novel');
      expect(result.sourceId, 'dune-1');
      expect(result.providerName, 'Example Books');
    });

    test('sends a JSON POST request with placeholders replaced', () async {
      final client = _RecordingClient(
        (request) async => http.Response('{"title":"JSON book"}', 200),
      );
      final source = _source(
        method: IsbnRequestMethod.post,
        postBodyMode: IsbnPostBodyMode.json,
        postBodyTemplate: '{"isbn":"{isbn}","key":"{apiKey}"}',
        titleJsonPath: r'$.title',
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore('secret'),
      ).lookup(isbn: isbn, sources: [source]);

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(
        request.headers['content-type'],
        startsWith('application/json'),
      );
      expect(request.body, '{"isbn":"$isbn","key":"secret"}');
      expect(result!.title, 'JSON book');
    });

    test('sends a form POST request with placeholders replaced', () async {
      final client = _RecordingClient(
        (request) async => http.Response('{"title":"Form book"}', 200),
      );
      final source = _source(
        method: IsbnRequestMethod.post,
        postBodyMode: IsbnPostBodyMode.formUrlEncoded,
        postBodyTemplate: 'isbn={isbn}&key={apiKey}',
        titleJsonPath: r'$.title',
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore('secret'),
      ).lookup(isbn: isbn, sources: [source]);

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(
        request.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(request.body, 'isbn=$isbn&key=secret');
      expect(result!.title, 'Form book');
    });

    test('short circuits after the first source returning a title', () async {
      final client = _RecordingClient((request) async => http.Response(
            '{"title":"First"}',
            200,
          ));

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'first', titleJsonPath: r'$.title'),
          _source(id: 'second', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'First');
      expect(client.requests, hasLength(1));
    });

    test('continues after a source has no result or an invalid response', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('not JSON', 200)
            : http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'broken', titleJsonPath: r'$.title'),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Fallback');
      expect(calls, 2);
    });

    test('continues after a non-success HTTP status', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('{"title":"Unavailable"}', 503)
            : http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'unavailable', titleJsonPath: r'$.title'),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Fallback');
      expect(calls, 2);
    });

    test('continues after an HTTP client exception', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'offline', titleJsonPath: r'$.title'),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Fallback');
      expect(calls, 2);
    });

    test('skips an invalid source mapping before making a request', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('{"title":"Ignored"}', 200)
            : http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'invalid-path', titleJsonPath: r'$.book['),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Ignored');
      expect(calls, 1);
    });

    test('continues after a whitespace-only mapped title', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('{"title":"   "}', 200)
            : http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(id: 'blank-title', titleJsonPath: r'$.title'),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Fallback');
      expect(calls, 2);
    });

    test('continues after a request times out', () async {
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        if (calls == 1) return Completer<http.Response>().future;
        return http.Response('{"title":"Fallback"}', 200);
      });

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(
        isbn: isbn,
        sources: [
          _source(
            timeout: const Duration(milliseconds: 1),
            titleJsonPath: r'$.title',
          ),
          _source(id: 'fallback', titleJsonPath: r'$.title'),
        ],
      );

      expect(result!.title, 'Fallback');
    });

    test('continues after a missing title and returns null when none match', () async {
      final client = _RecordingClient(
        (request) async => http.Response('{"author":"No title"}', 200),
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(isbn: isbn, sources: [_source(), _source(id: 'second')]);

      expect(result, isNull);
      expect(client.requests, hasLength(2));
    });

    test('maps JSONPath arrays into a comma-separated field', () async {
      final client = _RecordingClient((request) async => http.Response(
            '{"title":"Array book","authors":["Ada","Bob"]}',
            200,
          ));
      final source = _source(
        titleJsonPath: r'$.title',
        authorJsonPath: r'$.authors[*]',
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(null),
      ).lookup(isbn: isbn, sources: [source]);

      expect(result!.author, 'Ada, Bob');
    });

    test('only substitutes exact placeholders and never logs API keys', () async {
      final client = _RecordingClient(
        (request) async => http.Response('{"title":"Private"}', 200),
      );
      final source = _source(
        urlTemplate:
            'https://books.example/{isbn}?key={apiKey}&literal={api_key}',
        titleJsonPath: r'$.title',
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore('secret'),
      ).lookup(isbn: isbn, sources: [source]);

      final request = client.requests.single;
      expect(request.url.toString(), contains('key=secret'));
      expect(request.url.toString(), contains('%7Bapi_key%7D'));
      expect(result!.title, 'Private');
    });

    test('encodes URL placeholder values without changing query semantics', () async {
      const specialIsbn = '978/0?part=1&other=2';
      const specialApiKey = 'key/with?reserved&characters';
      final client = _RecordingClient((request) async {
        expect(request.url.queryParameters['isbn'], specialIsbn);
        expect(request.url.queryParameters['key'], specialApiKey);
        expect(request.url.toString(), contains('978%2F0%3Fpart%3D1%26other%3D2'));
        return http.Response('{"title":"Encoded"}', 200);
      });
      final source = _source(
        urlTemplate: 'https://books.example/lookup?isbn={isbn}&key={apiKey}',
        titleJsonPath: r'$.title',
      );

      final result = await CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(specialApiKey),
      ).lookup(isbn: specialIsbn, sources: [source]);

      expect(result!.title, 'Encoded');
    });

    test('keeps JSON and form placeholder values valid with special characters',
        () async {
      const specialIsbn = 'isbn"with\\slash';
      const specialApiKey = 'key&with=reserved';
      var calls = 0;
      final client = _RecordingClient((request) async {
        calls++;
        if (calls == 1) {
          expect(jsonDecode(request.body), {
            'isbn': specialIsbn,
            'key': specialApiKey,
          });
        } else {
          expect(Uri.splitQueryString(request.body), {
            'isbn': specialIsbn,
            'key': specialApiKey,
          });
        }
        return http.Response('{"title":"Encoded"}', 200);
      });

      final service = CustomIsbnLookupService(
        client: client,
        credentialsStore: _CredentialsStore(specialApiKey),
      );
      final jsonSource = _source(
        id: 'json',
        method: IsbnRequestMethod.post,
        postBodyMode: IsbnPostBodyMode.json,
        postBodyTemplate: '{"isbn":"{isbn}","key":"{apiKey}"}',
        titleJsonPath: r'$.title',
      );
      final formSource = _source(
        id: 'form',
        method: IsbnRequestMethod.post,
        postBodyMode: IsbnPostBodyMode.formUrlEncoded,
        postBodyTemplate: 'isbn={isbn}&key={apiKey}',
        titleJsonPath: r'$.title',
      );

      await service.lookup(isbn: specialIsbn, sources: [jsonSource]);
      await service.lookup(isbn: specialIsbn, sources: [formSource]);
      expect(calls, 2);
    });
  });
}

IsbnDataSource _source({
  String id = 'example',
  String urlTemplate = 'https://books.example/{isbn}?key={apiKey}',
  IsbnRequestMethod method = IsbnRequestMethod.get,
  IsbnPostBodyMode postBodyMode = IsbnPostBodyMode.none,
  String? postBodyTemplate,
  Duration timeout = const Duration(seconds: 1),
  String titleJsonPath = r'$.book.title',
  String? authorJsonPath,
}) =>
    IsbnDataSource(
      id: id,
      name: 'Example Books',
      enabled: true,
      method: method,
      urlTemplate: urlTemplate,
      headers: const {'x-token': '{apiKey}'},
      postBodyMode: postBodyMode,
      postBodyTemplate: postBodyTemplate,
      timeout: timeout,
      titleJsonPath: titleJsonPath,
      authorJsonPath: authorJsonPath ?? r'$.book.author',
      isbnJsonPath: r'$.book.isbn',
      pageCountJsonPath: r'$.book.pages',
      publicationYearJsonPath: r'$.book.year',
      coverUrlJsonPath: r'$.book.cover',
      publisherJsonPath: r'$.book.publisher',
      descriptionJsonPath: r'$.book.description',
      sourceIdJsonPath: r'$.book.id',
    );

class _CredentialsStore implements IsbnSourceCredentialsStore {
  _CredentialsStore(this.value);

  final String? value;

  @override
  Future<void> deleteApiKey(String sourceId) async {}

  @override
  Future<String?> readApiKey(String sourceId) async => value;

  @override
  Future<void> writeApiKey(String sourceId, String apiKey) async {}
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final buffered = request as http.Request;
    requests.add(buffered);
    final response = await handler(buffered);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
