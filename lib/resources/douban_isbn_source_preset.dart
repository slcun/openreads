import 'package:openreads/model/isbn_data_source.dart';

class DoubanIsbnSourcePreset {
  static const id = 'douban-isbn-proxy';

  static IsbnDataSource create(String baseUrl) {
    final baseUri = _httpsBaseUri(baseUrl);
    return IsbnDataSource(
      id: id,
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

  static Uri _httpsBaseUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Base URL must not be empty');
    }

    var normalized = trimmed;
    if (!normalized.endsWith('/')) {
      normalized = '$normalized/';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException(
        'Base URL must be a valid HTTPS URL with a host',
      );
    }

    return uri;
  }
}
