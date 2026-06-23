import 'package:flutter_test/flutter_test.dart';
import 'package:openreads/model/isbn_data_source.dart';

void main() {
  // ignore: prefer_const_constructors
  final source = IsbnDataSource(
    id: 'open-library',
    name: 'Open Library',
    enabled: true,
    method: IsbnRequestMethod.post,
    urlTemplate: 'https://example.com/books/{isbn}',
    headers: const {'Accept': 'application/json'},
    postBodyMode: IsbnPostBodyMode.json,
    postBodyTemplate: '{"isbn":"{isbn}"}',
    timeout: const Duration(seconds: 12),
    titleJsonPath: r'$.book.title',
    authorJsonPath: r'$.book.author',
    isbnJsonPath: r'$.book.isbn',
    pageCountJsonPath: r'$.book.pages',
    publicationYearJsonPath: r'$.book.publication_year',
    sourceIdJsonPath: r'$.book.id',
  );

  group('IsbnDataSource', () {
    test('serializes configuration without credentials', () {
      final json = source.toJson();

      expect(json['id'], 'open-library');
      expect(json['method'], 'post');
      expect(json['post_body_mode'], 'json');
      expect(json['isbn_json_path'], r'$.book.isbn');
      expect(json['page_count_json_path'], r'$.book.pages');
      expect(json['publication_year_json_path'], r'$.book.publication_year');
      expect(json.containsKey('api_key'), isFalse);
    });

    test('deserializes persisted configuration', () {
      final restored = IsbnDataSource.fromJson(source.toJson());

      expect(restored.id, source.id);
      expect(restored.headers, source.headers);
      expect(restored.isbnJsonPath, r'$.book.isbn');
      expect(restored.pageCountJsonPath, r'$.book.pages');
      expect(restored.publicationYearJsonPath, r'$.book.publication_year');
      expect(restored.sourceIdJsonPath, r'$.book.id');
    });

    test('validates a request and a title mapping separately', () {
      expect(source.hasValidRequestConfiguration, isTrue);
      expect(source.hasValidResponseMapping, isTrue);
      expect(source.isValid, isTrue);

      final invalidRequest = IsbnDataSource(
        id: 'invalid',
        name: 'Invalid',
        enabled: true,
        method: IsbnRequestMethod.get,
        urlTemplate: 'not a URL',
        titleJsonPath: r'$.title',
      );
      final invalidMapping = IsbnDataSource(
        id: 'no-title',
        name: 'No title',
        enabled: true,
        method: IsbnRequestMethod.get,
        urlTemplate: 'https://example.com/{isbn}',
        titleJsonPath: '',
      );

      expect(invalidRequest.hasValidRequestConfiguration, isFalse);
      expect(invalidMapping.hasValidResponseMapping, isFalse);
    });

    test('accepts HTTP URLs for trusted local hosts', () {
      for (final url in [
        'http://localhost:8080/books/{isbn}',
        'http://nas.local/books/{isbn}',
        'http://192.168.1.20/books/{isbn}',
        'http://[fd00::20]/books/{isbn}',
      ]) {
        final source = IsbnDataSource(
          id: 'local-http',
          name: 'Local HTTP',
          enabled: true,
          method: IsbnRequestMethod.get,
          urlTemplate: url,
          titleJsonPath: r'$.title',
        );

        expect(source.validate(), isTrue, reason: url);
      }
    });

    test('rejects HTTP URLs for public hosts', () {
      final source = IsbnDataSource(
        id: 'public-http',
        name: 'Public HTTP',
        enabled: true,
        method: IsbnRequestMethod.get,
        urlTemplate: 'http://example.com/books/{isbn}',
        titleJsonPath: r'$.title',
      );

      expect(source.validate(), isFalse);
    });

    test('rejects a request without an ISBN placeholder', () {
      final source = IsbnDataSource(
        id: 'missing-isbn',
        name: 'Missing ISBN',
        enabled: true,
        method: IsbnRequestMethod.post,
        urlTemplate: 'https://example.com/books',
        postBodyMode: IsbnPostBodyMode.json,
        postBodyTemplate: '{"query":"book"}',
        titleJsonPath: r'$.title',
      );

      expect(source.validate(), isFalse);
    });

    test(
      'rejects a JSON POST body that is invalid after ISBN substitution',
      () {
        final source = IsbnDataSource(
          id: 'invalid-json',
          name: 'Invalid JSON',
          enabled: true,
          method: IsbnRequestMethod.post,
          urlTemplate: 'https://example.com/books',
          postBodyMode: IsbnPostBodyMode.json,
          postBodyTemplate: 'isbn={isbn}',
          titleJsonPath: r'$.title',
        );

        expect(source.hasValidRequestConfiguration, isFalse);
      },
    );
  });
}
