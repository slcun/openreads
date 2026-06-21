import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:openreads/generated/locale_keys.g.dart';
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/model/isbn_lookup_result.dart';
import 'package:openreads/resources/custom_isbn_lookup_service.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';

class IsbnDataSourceEditorScreen extends StatefulWidget {
  const IsbnDataSourceEditorScreen({super.key, this.source});

  final IsbnDataSource? source;

  @override
  State<IsbnDataSourceEditorScreen> createState() =>
      _IsbnDataSourceEditorScreenState();
}

class _IsbnDataSourceEditorScreenState extends State<IsbnDataSourceEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _urlTemplate = TextEditingController();
  final _headers = TextEditingController();
  final _bodyTemplate = TextEditingController();
  final _timeout = TextEditingController();
  final _apiKey = TextEditingController();
  final _testIsbn = TextEditingController(text: '9780306406157');
  final _titlePath = TextEditingController();
  final _authorPath = TextEditingController();
  final _isbnPath = TextEditingController();
  final _pageCountPath = TextEditingController();
  final _coverUrlPath = TextEditingController();
  final _publisherPath = TextEditingController();
  final _publicationYearPath = TextEditingController();
  final _descriptionPath = TextEditingController();
  final _sourceIdPath = TextEditingController();
  late final String _id;
  late IsbnRequestMethod _method;
  late IsbnPostBodyMode _bodyMode;
  IsbnLookupResult? _preview;
  String? _testError;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _id = source?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _method = source?.method ?? IsbnRequestMethod.get;
    _bodyMode = source?.postBodyMode ?? IsbnPostBodyMode.none;
    _name.text = source?.name ?? '';
    _urlTemplate.text = source?.urlTemplate ?? '';
    _headers.text = source?.headers.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n') ?? '';
    _bodyTemplate.text = source?.postBodyTemplate ?? '';
    _timeout.text = (source?.timeout.inSeconds ?? 10).toString();
    _titlePath.text = source?.titleJsonPath ?? '';
    _authorPath.text = source?.authorJsonPath ?? '';
    _isbnPath.text = source?.isbnJsonPath ?? '';
    _pageCountPath.text = source?.pageCountJsonPath ?? '';
    _coverUrlPath.text = source?.coverUrlJsonPath ?? '';
    _publisherPath.text = source?.publisherJsonPath ?? '';
    _publicationYearPath.text = source?.publicationYearJsonPath ?? '';
    _descriptionPath.text = source?.descriptionJsonPath ?? '';
    _sourceIdPath.text = source?.sourceIdJsonPath ?? '';
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final apiKey = await context.read<IsbnSourceCredentialsStore>().readApiKey(_id);
    if (mounted && apiKey != null) _apiKey.text = apiKey;
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _urlTemplate, _headers, _bodyTemplate, _timeout, _apiKey, _testIsbn,
      _titlePath, _authorPath, _isbnPath, _pageCountPath, _coverUrlPath,
      _publisherPath, _publicationYearPath, _descriptionPath, _sourceIdPath,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> _parseHeaders() {
    final headers = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final separator = line.indexOf(':');
      if (separator > 0) {
        headers[line.substring(0, separator).trim()] = line.substring(separator + 1).trim();
      }
    }
    return headers;
  }

  bool get _hasValidHeaderLines => _headers.text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .every((line) {
        final separator = line.indexOf(':');
        return separator > 0 &&
            _isHttpToken(line.substring(0, separator).trim());
      });

  bool _isHttpToken(String value) {
    if (value.isEmpty) return false;
    for (final codeUnit in value.codeUnits) {
      final isLetter = (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122);
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      const tokenSymbols = <int>{
        33,
        35,
        36,
        37,
        38,
        39,
        42,
        43,
        45,
        46,
        94,
        95,
        96,
        124,
        126,
      };
      if (!isLetter && !isDigit && !tokenSymbols.contains(codeUnit)) {
        return false;
      }
    }
    return true;
  }

  String? _optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  IsbnDataSource _source() => IsbnDataSource(
        id: _id,
        name: _name.text.trim(),
        enabled: widget.source?.enabled ?? true,
        method: _method,
        urlTemplate: _urlTemplate.text.trim(),
        headers: _parseHeaders(),
        postBodyMode: _bodyMode,
        postBodyTemplate: _optional(_bodyTemplate),
        timeout: Duration(seconds: int.tryParse(_timeout.text) ?? 0),
        titleJsonPath: _titlePath.text.trim(),
        authorJsonPath: _optional(_authorPath),
        isbnJsonPath: _optional(_isbnPath),
        pageCountJsonPath: _optional(_pageCountPath),
        coverUrlJsonPath: _optional(_coverUrlPath),
        publisherJsonPath: _optional(_publisherPath),
        publicationYearJsonPath: _optional(_publicationYearPath),
        descriptionJsonPath: _optional(_descriptionPath),
        sourceIdJsonPath: _optional(_sourceIdPath),
      );

  Future<void> _save() async {
    final source = _source();
    if (!(_formKey.currentState?.validate() ?? false) ||
        !source.validate() ||
        !_hasValidHeaderLines) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleKeys.isbn_data_source_invalid.tr())),
      );
      return;
    }
    final store = context.read<IsbnSourceCredentialsStore>();
    if (_apiKey.text.trim().isEmpty) {
      await store.deleteApiKey(source.id);
    } else {
      await store.writeApiKey(source.id, _apiKey.text.trim());
    }
    if (!mounted) return;
    context.read<IsbnDataSourcesCubit>().save(source);
    Navigator.of(context).pop();
  }

  Future<void> _test() async {
    final source = _source();
    if (!source.validate() ||
        !_hasValidHeaderLines ||
        _testIsbn.text.trim().isEmpty) {
      setState(() => _testError = LocaleKeys.isbn_data_source_invalid.tr());
      return;
    }
    setState(() { _testing = true; _testError = null; _preview = null; });
    try {
      final result = await context.read<CustomIsbnLookupService>().lookup(
        isbn: _testIsbn.text.trim(),
        sources: [source],
        apiKeyOverride:
            _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
        useApiKeyOverride: true,
      );
      if (!mounted) return;
      setState(() {
        _preview = result;
        _testError = result == null ? LocaleKeys.isbn_data_source_test_failed.tr() : null;
      });
    } catch (_) {
      if (mounted) setState(() => _testError = LocaleKeys.isbn_data_source_test_failed.tr());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(LocaleKeys.isbn_data_source_editor.tr())),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _field(_name, LocaleKeys.isbn_data_source_name.tr(), key: const Key('isbn-source-name'), required: true),
              _field(_urlTemplate, LocaleKeys.isbn_data_source_url_template.tr(), key: const Key('isbn-source-url-template'), required: true),
              DropdownButtonFormField<IsbnRequestMethod>(
                value: _method, decoration: InputDecoration(labelText: LocaleKeys.isbn_data_source_method.tr()),
                items: IsbnRequestMethod.values
                    .map((method) => DropdownMenuItem(
                          value: method,
                          child: Text(_methodLabel(method)),
                        ))
                    .toList(),
                onChanged: (method) => setState(() => _method = method!),
              ),
              _field(
                _headers,
                LocaleKeys.isbn_data_source_headers.tr(),
                key: const Key('isbn-source-headers'),
                maxLines: 3,
              ),
              if (_method == IsbnRequestMethod.post) ...[
                DropdownButtonFormField<IsbnPostBodyMode>(
                  value: _bodyMode, decoration: InputDecoration(labelText: LocaleKeys.isbn_data_source_body_mode.tr()),
                  items: IsbnPostBodyMode.values
                      .map((mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(_bodyModeLabel(mode)),
                          ))
                      .toList(),
                  onChanged: (mode) => setState(() => _bodyMode = mode!),
                ),
                if (_bodyMode != IsbnPostBodyMode.none) _field(_bodyTemplate, LocaleKeys.isbn_data_source_body_template.tr(), maxLines: 3),
              ],
              _field(_timeout, LocaleKeys.isbn_data_source_timeout.tr(), keyboardType: TextInputType.number),
              _field(_apiKey, LocaleKeys.isbn_data_source_api_key.tr(), obscure: true, key: const Key('isbn-source-api-key')),
              const Divider(height: 32),
              Text(LocaleKeys.isbn_data_source_response_mapping.tr(), style: Theme.of(context).textTheme.titleMedium),
              _field(_titlePath, LocaleKeys.isbn_data_source_title_path.tr(), key: const Key('isbn-source-title-path'), required: true),
              _field(_authorPath, LocaleKeys.isbn_data_source_author_path.tr()),
              _field(_isbnPath, LocaleKeys.isbn_data_source_isbn_path.tr()),
              _field(_pageCountPath, LocaleKeys.isbn_data_source_page_count_path.tr()),
              _field(_coverUrlPath, LocaleKeys.isbn_data_source_cover_url_path.tr()),
              _field(_publisherPath, LocaleKeys.isbn_data_source_publisher_path.tr()),
              _field(_publicationYearPath, LocaleKeys.isbn_data_source_publication_year_path.tr()),
              _field(_descriptionPath, LocaleKeys.isbn_data_source_description_path.tr()),
              _field(_sourceIdPath, LocaleKeys.isbn_data_source_source_id_path.tr()),
              const Divider(height: 32),
              _field(_testIsbn, LocaleKeys.isbn_data_source_test_isbn.tr(), key: const Key('isbn-source-test-isbn')),
              FilledButton(
                key: const Key('isbn-source-test'), onPressed: _testing ? null : _test,
                child: Text(LocaleKeys.isbn_data_source_test.tr()),
              ),
              if (_testing) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
              if (_testError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_testError!)),
              if (_preview != null) ListTile(title: Text(_preview!.title), subtitle: Text(_preview!.providerName)),
              const SizedBox(height: 16),
              FilledButton(key: const Key('isbn-source-save'), onPressed: _save, child: Text(LocaleKeys.save.tr())),
            ],
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label, {Key? key, bool required = false, bool obscure = false, int maxLines = 1, TextInputType? keyboardType}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: key, controller: controller, obscureText: obscure, maxLines: obscure ? 1 : maxLines, keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: required ? (value) => value == null || value.trim().isEmpty ? LocaleKeys.isbn_data_source_required.tr() : null : null,
        ),
      );

  String _methodLabel(IsbnRequestMethod method) => method == IsbnRequestMethod.get
      ? LocaleKeys.isbn_data_source_get.tr()
      : LocaleKeys.isbn_data_source_post.tr();

  String _bodyModeLabel(IsbnPostBodyMode mode) {
    switch (mode) {
      case IsbnPostBodyMode.none:
        return LocaleKeys.isbn_data_source_body_none.tr();
      case IsbnPostBodyMode.json:
        return LocaleKeys.isbn_data_source_body_json.tr();
      case IsbnPostBodyMode.formUrlEncoded:
        return LocaleKeys.isbn_data_source_body_form.tr();
    }
  }
}
