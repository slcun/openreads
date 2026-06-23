import 'package:flutter_test/flutter_test.dart';
import 'package:openreads/resources/douban_isbn_source_preset.dart';

void main() {
  group('DoubanIsbnSourcePreset', () {
    test('creates a top-priority Douban source from an HTTPS base URL', () {
      final source =
          DoubanIsbnSourcePreset.create('https://books.example/proxy/');
      expect(source.id, 'douban-isbn-proxy');
      expect(source.urlTemplate,
          'https://books.example/proxy/v1/books/isbn/{isbn}');
      expect(source.titleJsonPath, r'$.title');
      expect(source.authorJsonPath, r'$.authors[*]');
      expect(source.sourceIdJsonPath, r'$.source_id');
    });

    test('rejects a non-HTTPS base URL', () {
      expect(
        () => DoubanIsbnSourcePreset.create('http://192.168.1.2:8080'),
        throwsFormatException,
      );
    });

    test('rejects an empty string', () {
      expect(
        () => DoubanIsbnSourcePreset.create(''),
        throwsFormatException,
      );
    });

    test('rejects a URL without a host', () {
      expect(
        () => DoubanIsbnSourcePreset.create('https://'),
        throwsFormatException,
      );
    });

    test('normalizes a base URL without trailing slash', () {
      final source =
          DoubanIsbnSourcePreset.create('https://books.example/proxy');
      expect(source.urlTemplate,
          'https://books.example/proxy/v1/books/isbn/{isbn}');
    });

    test('trims whitespace from the base URL', () {
      final source =
          DoubanIsbnSourcePreset.create('  https://books.example/proxy/  ');
      expect(source.urlTemplate,
          'https://books.example/proxy/v1/books/isbn/{isbn}');
    });
  });
}
