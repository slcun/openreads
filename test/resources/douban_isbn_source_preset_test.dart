import 'package:flutter_test/flutter_test.dart';
import 'package:openreads/resources/douban_isbn_source_preset.dart';

void main() {
  group('DoubanIsbnSourcePreset', () {
    test('creates a top-priority Douban source from an HTTPS base URL', () {
      final source = DoubanIsbnSourcePreset.create(
        'https://books.example/proxy/',
      );
      expect(source.id, startsWith('douban-isbn-proxy-'));
      expect(
        source.urlTemplate,
        'https://books.example/proxy/v1/books/isbn/{isbn}',
      );
      expect(source.titleJsonPath, r'$.title');
      expect(source.authorJsonPath, r'$.authors[*]');
      expect(source.sourceIdJsonPath, r'$.source_id');
    });

    test('creates a distinct source ID for every proxy', () {
      final first = DoubanIsbnSourcePreset.create(
        'https://first.example/proxy/',
      );
      final second = DoubanIsbnSourcePreset.create(
        'https://second.example/proxy/',
      );

      expect(first.id, isNot(second.id));
    });

    test('creates a source from a trusted local HTTP base URL', () {
      final source = DoubanIsbnSourcePreset.create('http://192.168.1.2:8080');

      expect(
        source.urlTemplate,
        'http://192.168.1.2:8080/v1/books/isbn/{isbn}',
      );
    });

    test('rejects a public HTTP base URL', () {
      expect(
        () => DoubanIsbnSourcePreset.create('http://books.example'),
        throwsFormatException,
      );
    });

    test('rejects an empty string', () {
      expect(() => DoubanIsbnSourcePreset.create(''), throwsFormatException);
    });

    test('rejects a URL without a host', () {
      expect(
        () => DoubanIsbnSourcePreset.create('https://'),
        throwsFormatException,
      );
    });

    test('normalizes a base URL without trailing slash', () {
      final source = DoubanIsbnSourcePreset.create(
        'https://books.example/proxy',
      );
      expect(
        source.urlTemplate,
        'https://books.example/proxy/v1/books/isbn/{isbn}',
      );
    });

    test('trims whitespace from the base URL', () {
      final source = DoubanIsbnSourcePreset.create(
        '  https://books.example/proxy/  ',
      );
      expect(
        source.urlTemplate,
        'https://books.example/proxy/v1/books/isbn/{isbn}',
      );
    });
  });
}
