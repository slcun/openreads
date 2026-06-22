import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum IsbnRequestMethod { get, post }

enum IsbnPostBodyMode { none, json, formUrlEncoded }

@immutable
class IsbnDataSource {
  IsbnDataSource({
    required this.id,
    required this.name,
    required this.enabled,
    required this.method,
    required this.urlTemplate,
    Map<String, String> headers = const {},
    this.postBodyMode = IsbnPostBodyMode.none,
    this.postBodyTemplate,
    this.timeout = const Duration(seconds: 10),
    required this.titleJsonPath,
    this.authorJsonPath,
    this.isbnJsonPath,
    this.pageCountJsonPath,
    this.coverUrlJsonPath,
    this.publisherJsonPath,
    this.publicationYearJsonPath,
    this.descriptionJsonPath,
    this.sourceIdJsonPath,
  }) : headers = UnmodifiableMapView(Map<String, String>.from(headers));

  final String id;
  final String name;
  final bool enabled;
  final IsbnRequestMethod method;
  final String urlTemplate;
  final Map<String, String> headers;
  final IsbnPostBodyMode postBodyMode;
  final String? postBodyTemplate;
  final Duration timeout;
  final String titleJsonPath;
  final String? authorJsonPath;
  final String? isbnJsonPath;
  final String? pageCountJsonPath;
  final String? coverUrlJsonPath;
  final String? publisherJsonPath;
  final String? publicationYearJsonPath;
  final String? descriptionJsonPath;
  final String? sourceIdJsonPath;

  bool get hasValidRequestConfiguration {
    final uri = Uri.tryParse(urlTemplate);
    if (id.trim().isEmpty || name.trim().isEmpty || uri == null ||
        uri.scheme != 'https' || uri.host.isEmpty || timeout <= Duration.zero) {
      return false;
    }

    final usesIsbnInUrl = urlTemplate.contains('{isbn}');
    final usesIsbnInBody = postBodyTemplate?.contains('{isbn}') ?? false;
    if (method == IsbnRequestMethod.get) return usesIsbnInUrl;

    if (postBodyMode == IsbnPostBodyMode.none) return usesIsbnInUrl;

    final bodyTemplate = postBodyTemplate?.trim();
    if (bodyTemplate == null || bodyTemplate.isEmpty ||
        (!usesIsbnInUrl && !usesIsbnInBody)) {
      return false;
    }

    return postBodyMode != IsbnPostBodyMode.json ||
        _isValidJsonTemplate(bodyTemplate);
  }

  bool get hasValidResponseMapping {
    return _isValidJsonPath(titleJsonPath) &&
        [
          authorJsonPath,
          isbnJsonPath,
          pageCountJsonPath,
          coverUrlJsonPath,
          publisherJsonPath,
          publicationYearJsonPath,
          descriptionJsonPath,
          sourceIdJsonPath,
        ].every(_isEmptyOrValidJsonPath);
  }

  bool get isValid =>
      hasValidRequestConfiguration && hasValidResponseMapping;

  bool validate() => isValid;

  IsbnDataSource copyWith({
    String? id,
    String? name,
    bool? enabled,
    IsbnRequestMethod? method,
    String? urlTemplate,
    Map<String, String>? headers,
    IsbnPostBodyMode? postBodyMode,
    String? postBodyTemplate,
    bool clearPostBodyTemplate = false,
    Duration? timeout,
    String? titleJsonPath,
    String? authorJsonPath,
    String? isbnJsonPath,
    String? pageCountJsonPath,
    String? coverUrlJsonPath,
    String? publisherJsonPath,
    String? publicationYearJsonPath,
    String? descriptionJsonPath,
    String? sourceIdJsonPath,
  }) {
    return IsbnDataSource(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      method: method ?? this.method,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      headers: headers ?? this.headers,
      postBodyMode: postBodyMode ?? this.postBodyMode,
      postBodyTemplate: clearPostBodyTemplate
          ? null
          : postBodyTemplate ?? this.postBodyTemplate,
      timeout: timeout ?? this.timeout,
      titleJsonPath: titleJsonPath ?? this.titleJsonPath,
      authorJsonPath: authorJsonPath ?? this.authorJsonPath,
      isbnJsonPath: isbnJsonPath ?? this.isbnJsonPath,
      pageCountJsonPath: pageCountJsonPath ?? this.pageCountJsonPath,
      coverUrlJsonPath: coverUrlJsonPath ?? this.coverUrlJsonPath,
      publisherJsonPath: publisherJsonPath ?? this.publisherJsonPath,
      publicationYearJsonPath:
          publicationYearJsonPath ?? this.publicationYearJsonPath,
      descriptionJsonPath: descriptionJsonPath ?? this.descriptionJsonPath,
      sourceIdJsonPath: sourceIdJsonPath ?? this.sourceIdJsonPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'method': method.name,
        'url_template': urlTemplate,
        'headers': headers,
        'post_body_mode': postBodyMode.name,
        'post_body_template': postBodyTemplate,
        'timeout_ms': timeout.inMilliseconds,
        'title_json_path': titleJsonPath,
        'author_json_path': authorJsonPath,
        'isbn_json_path': isbnJsonPath,
        'page_count_json_path': pageCountJsonPath,
        'cover_url_json_path': coverUrlJsonPath,
        'publisher_json_path': publisherJsonPath,
        'publication_year_json_path': publicationYearJsonPath,
        'description_json_path': descriptionJsonPath,
        'source_id_json_path': sourceIdJsonPath,
      };

  factory IsbnDataSource.fromJson(Map<String, dynamic> json) {
    return IsbnDataSource(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      method: _requestMethodFromJson(json['method'] as String?),
      urlTemplate: json['url_template'] as String,
      headers: _headersFromJson(json['headers']),
      postBodyMode: _postBodyModeFromJson(json['post_body_mode'] as String?),
      postBodyTemplate: json['post_body_template'] as String?,
      timeout: Duration(milliseconds: json['timeout_ms'] as int? ?? 10000),
      titleJsonPath: json['title_json_path'] as String,
      authorJsonPath: json['author_json_path'] as String?,
      isbnJsonPath: json['isbn_json_path'] as String?,
      pageCountJsonPath: json['page_count_json_path'] as String?,
      coverUrlJsonPath: json['cover_url_json_path'] as String?,
      publisherJsonPath: json['publisher_json_path'] as String?,
      publicationYearJsonPath: json['publication_year_json_path'] as String?,
      descriptionJsonPath: json['description_json_path'] as String?,
      sourceIdJsonPath: json['source_id_json_path'] as String?,
    );
  }

  static IsbnRequestMethod _requestMethodFromJson(String? value) {
    return value == IsbnRequestMethod.post.name
        ? IsbnRequestMethod.post
        : IsbnRequestMethod.get;
  }

  static IsbnPostBodyMode _postBodyModeFromJson(String? value) {
    return IsbnPostBodyMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => IsbnPostBodyMode.none,
    );
  }

  static Map<String, String> _headersFromJson(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, headerValue) => MapEntry(
          key.toString(),
          headerValue.toString(),
        ));
  }

  static bool _isValidJsonPath(String value) {
    final path = value.trim();
    if (!path.startsWith(r'$')) return false;

    var index = 1;
    while (index < path.length) {
      if (path[index] == '.') {
        final start = ++index;
        while (index < path.length &&
            path[index] != '.' &&
            path[index] != '[') {
          index++;
        }
        if (index == start) return false;
      } else if (path[index] == '[') {
        final close = path.indexOf(']', index + 1);
        if (close == -1) return false;
        final selector = path.substring(index + 1, close);
        if (selector != '*' && int.tryParse(selector) == null) return false;
        index = close + 1;
      } else {
        return false;
      }
    }
    return true;
  }

  static bool _isEmptyOrValidJsonPath(String? value) =>
      value == null || value.trim().isEmpty || _isValidJsonPath(value);

  static bool _isValidJsonTemplate(String template) {
    try {
      jsonDecode(template.replaceAll('{isbn}', '9780306406157'));
      return true;
    } on FormatException {
      return false;
    }
  }
}
