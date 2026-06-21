import 'package:flutter/foundation.dart';

@immutable
class IsbnLookupResult {
  const IsbnLookupResult({
    required this.title,
    required this.providerName,
    this.author,
    this.isbn,
    this.coverUrl,
    this.publisher,
    this.publicationYear,
    this.pageCount,
    this.description,
    this.sourceId,
  });

  final String title;
  final String providerName;
  final String? author;
  final String? isbn;
  final String? coverUrl;
  final String? publisher;
  final int? publicationYear;
  final int? pageCount;
  final String? description;
  final String? sourceId;
}
