import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/model/isbn_lookup_result.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';

class CustomIsbnLookupService {
  CustomIsbnLookupService({
    required http.Client client,
    required IsbnSourceCredentialsStore credentialsStore,
  })  : _client = client,
        _credentialsStore = credentialsStore;

  final http.Client _client;
  final IsbnSourceCredentialsStore _credentialsStore;

  Future<IsbnLookupResult?> lookup({
    required String isbn,
    required List<IsbnDataSource> sources,
    String? apiKeyOverride,
    bool useApiKeyOverride = false,
  }) async {
    for (final source in sources) {
      if (!source.enabled || !source.isValid) continue;

      try {
        final apiKey = useApiKeyOverride
            ? apiKeyOverride
            : await _credentialsStore.readApiKey(source.id);
        final response = await _send(source, isbn, apiKey);
        if (response.statusCode < 200 || response.statusCode >= 300) continue;

        final decoded = jsonDecode(response.body);
        final result = _mapResult(source, decoded);
        if (result != null) return result;
      } catch (_) {
        // A source is independent; failures must not prevent fallbacks.
      }
    }
    return null;
  }

  Future<http.Response> _send(
    IsbnDataSource source,
    String isbn,
    String? apiKey,
  ) {
    final request = http.Request(
      source.method.name.toUpperCase(),
      Uri.parse(_replaceUrlTemplate(source.urlTemplate, isbn, apiKey)),
    );
    request.headers.addAll(source.headers.map(
      (name, value) => MapEntry(name, _replaceRaw(value, isbn, apiKey)),
    ));

    if (source.method == IsbnRequestMethod.post &&
        source.postBodyMode != IsbnPostBodyMode.none) {
      if (source.postBodyMode == IsbnPostBodyMode.json) {
        request.headers['content-type'] = 'application/json';
      } else {
        request.headers['content-type'] = 'application/x-www-form-urlencoded';
      }
      request.body = source.postBodyMode == IsbnPostBodyMode.json
          ? _replaceJsonTemplate(source.postBodyTemplate ?? '', isbn, apiKey)
          : _replaceFormTemplate(source.postBodyTemplate ?? '', isbn, apiKey);
    }

    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(source.timeout);
  }

  IsbnLookupResult? _mapResult(IsbnDataSource source, dynamic json) {
    final title = _stringAt(json, source.titleJsonPath)?.trim();
    if (title == null || title.isEmpty) return null;

    return IsbnLookupResult(
      title: title,
      author: _stringAt(json, source.authorJsonPath),
      isbn: _stringAt(json, source.isbnJsonPath),
      coverUrl: _stringAt(json, source.coverUrlJsonPath),
      publisher: _stringAt(json, source.publisherJsonPath),
      publicationYear: _intAt(json, source.publicationYearJsonPath),
      pageCount: _intAt(json, source.pageCountJsonPath),
      description: _stringAt(json, source.descriptionJsonPath),
      sourceId: _stringAt(json, source.sourceIdJsonPath),
      providerName: source.name,
    );
  }

  String? _stringAt(dynamic json, String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final values = _readJsonPath(json, path);
    if (values.isEmpty) return null;
    final value = values
        .expand((value) => value is List ? value : [value])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
    return value.isEmpty ? null : value;
  }

  int? _intAt(dynamic json, String? path) {
    final value = _stringAt(json, path);
    return value == null ? null : int.tryParse(value);
  }

  String _replaceUrlTemplate(String template, String isbn, String? apiKey) {
    return template
        .replaceAll('{isbn}', Uri.encodeComponent(isbn))
        .replaceAll('{apiKey}', Uri.encodeComponent(apiKey ?? ''));
  }

  String _replaceRaw(String template, String isbn, String? apiKey) {
    return template
        .replaceAll('{isbn}', isbn)
        .replaceAll('{apiKey}', apiKey ?? '');
  }

  String _replaceJsonTemplate(String template, String isbn, String? apiKey) {
    return template
        .replaceAll('{isbn}', _jsonStringContent(isbn))
        .replaceAll('{apiKey}', _jsonStringContent(apiKey ?? ''));
  }

  String _replaceFormTemplate(String template, String isbn, String? apiKey) {
    return template
        .replaceAll('{isbn}', Uri.encodeQueryComponent(isbn))
        .replaceAll('{apiKey}', Uri.encodeQueryComponent(apiKey ?? ''));
  }

  String _jsonStringContent(String value) {
    final encoded = jsonEncode(value);
    return encoded.substring(1, encoded.length - 1);
  }

  List<dynamic> _readJsonPath(dynamic value, String path) {
    if (!path.startsWith(r'$')) throw const FormatException('Invalid JSONPath');
    var index = 1;
    var values = <dynamic>[value];

    while (index < path.length) {
      if (path[index] == '.') {
        final end = _nextPathDelimiter(path, index + 1);
        final key = path.substring(index + 1, end);
        if (key.isEmpty) throw const FormatException('Invalid JSONPath');
        values = values
            .whereType<Map>()
            .where((item) => item.containsKey(key))
            .map((item) => item[key])
            .toList();
        index = end;
      } else if (path[index] == '[') {
        final close = path.indexOf(']', index + 1);
        if (close == -1) throw const FormatException('Invalid JSONPath');
        final selector = path.substring(index + 1, close);
        if (selector == '*') {
          values = values.expand(_wildcardValues).toList();
        } else {
          final listIndex = int.tryParse(selector);
          if (listIndex == null) throw const FormatException('Invalid JSONPath');
          values = values
              .whereType<List>()
              .where((item) => listIndex >= 0 && listIndex < item.length)
              .map((item) => item[listIndex])
              .toList();
        }
        index = close + 1;
      } else {
        throw const FormatException('Invalid JSONPath');
      }
    }
    return values;
  }

  int _nextPathDelimiter(String path, int start) {
    var index = start;
    while (index < path.length && path[index] != '.' && path[index] != '[') {
      index++;
    }
    return index;
  }

  Iterable<dynamic> _wildcardValues(dynamic value) {
    if (value is List) return value;
    if (value is Map) return value.values;
    return const [];
  }
}
