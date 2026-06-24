import 'package:openreads/model/isbn_data_source.dart';

class DoubanIsbnSourcePreset {
  static const _idPrefix = 'douban-isbn-proxy';
  static int _lastGeneratedIdTimestamp = 0;

  static IsbnDataSource create(String baseUrl) {
    final baseUri = _allowedBaseUri(baseUrl);
    return IsbnDataSource(
      id: _nextId(),
      name: 'Douban ISBN Proxy',
      enabled: true,
      method: IsbnRequestMethod.get,
      urlTemplate: '${baseUri.toString()}v1/books/isbn/{isbn}',
      titleJsonPath: r'$.title',
      authorJsonPath: r'$.authors[*]',
      isbnJsonPath: r'$.isbn',
      coverUrlJsonPath: r'$.cover_url',
      publisherJsonPath: r'$.publisher',
      publicationYearJsonPath: r'$.publication_year',
      pageCountJsonPath: r'$.page_count',
      descriptionJsonPath: r'$.description',
      sourceIdJsonPath: r'$.source_id',
    );
  }

  static String _nextId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final timestamp = now > _lastGeneratedIdTimestamp
        ? now
        : _lastGeneratedIdTimestamp + 1;
    _lastGeneratedIdTimestamp = timestamp;
    return '$_idPrefix-$timestamp';
  }

  static Uri _allowedBaseUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Base URL must not be empty');
    }

    var normalized = trimmed;
    if (!normalized.endsWith('/')) {
      normalized = '$normalized/';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !IsbnDataSource.isAllowedRequestUri(uri) ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Base URL must be a valid HTTPS URL or trusted local HTTP URL with a host',
      );
    }

    return uri;
  }
}
