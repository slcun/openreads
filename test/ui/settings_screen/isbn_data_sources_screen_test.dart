import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/model/isbn_lookup_result.dart';
import 'package:openreads/resources/custom_isbn_lookup_service.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';
import 'package:openreads/ui/settings_screen/isbn_data_source_editor_screen.dart';
import 'package:openreads/ui/settings_screen/isbn_data_sources_screen.dart';
import '../../test_helpers/in_memory_storage.dart';

void main() {
  setUp(() {
    HydratedBloc.storage = InMemoryStorage();
  });

  tearDown(() async {
    await HydratedBloc.storage.clear();
  });

  testWidgets('reorders ISBN sources from the list', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    addTearDown(cubit.close);
    cubit.save(_source(id: 'first', name: 'First source'));
    cubit.save(_source(id: 'second', name: 'Second source'));

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: _app(child: const IsbnDataSourcesScreen()),
      ),
    );

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(list.onReorderItem, isNotNull);
    list.onReorderItem!(0, 1);
    await tester.pump();

    expect(cubit.state.map((source) => source.id), ['second', 'first']);
  });

  testWidgets('editor saves valid source and keeps API keys out of cubit state',
      (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final credentials = _CredentialsStore();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: credentials,
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(
            value: _LookupService(),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: const IsbnDataSourceEditorScreen()),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('isbn-source-name')), 'Demo');
    await tester.enterText(
      find.byKey(const Key('isbn-source-url-template')),
      'https://books.example/{isbn}',
    );
    await tester.enterText(
      find.byKey(const Key('isbn-source-title-path')),
      r'$.title',
    );
    await tester.enterText(
      find.byKey(const Key('isbn-source-api-key')),
      'private-key',
    );
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-save')));
    await tester.tap(find.byKey(const Key('isbn-source-save')));
    await tester.pumpAndSettle();

    expect(cubit.state.single.name, 'Demo');
    expect(cubit.state.single.toJson().values.join(), isNot(contains('private-key')));
    expect(await credentials.readApiKey(cubit.state.single.id), 'private-key');
  });

  testWidgets('editor previews a successful ISBN lookup', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    addTearDown(cubit.close);
    final source = _source();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: _CredentialsStore(),
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(
            value: _LookupService(),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: IsbnDataSourceEditorScreen(source: source)),
        ),
      ),
    );

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('isbn-source-test-isbn')),
    );
    await tester.enterText(
      find.byKey(const Key('isbn-source-test-isbn')),
      '9780306406157',
    );
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-test')));
    await tester.tap(find.byKey(const Key('isbn-source-test')));
    await tester.pumpAndSettle();

    expect(find.text('Preview title'), findsOneWidget);
  });

  testWidgets('editor test uses the current API key without persisting it',
      (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final credentials = _CredentialsStore();
    final lookup = _LookupService();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: credentials,
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(value: lookup),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: IsbnDataSourceEditorScreen(source: _source())),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('isbn-source-api-key')),
      'unsaved-secret',
    );
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-test')));
    await tester.tap(find.byKey(const Key('isbn-source-test')));
    await tester.pumpAndSettle();

    expect(lookup.apiKeyOverride, 'unsaved-secret');
    expect(await credentials.readApiKey('source'), isNull);
  });

  testWidgets('editor presents a sanitized test error', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: _CredentialsStore(),
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(
            value: _ThrowingLookupService(),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: IsbnDataSourceEditorScreen(source: _source())),
        ),
      ),
    );

    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-test')));
    await tester.tap(find.byKey(const Key('isbn-source-test')));
    await tester.pumpAndSettle();

    expect(find.text('isbn_data_source_test_failed'), findsOneWidget);
    expect(find.textContaining('private request failure'), findsNothing);
  });

  testWidgets('editor rejects a header name containing whitespace',
      (tester) async {
    final cubit = IsbnDataSourcesCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: _CredentialsStore(),
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(
            value: _LookupService(),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: IsbnDataSourceEditorScreen(source: _source())),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('isbn-source-headers')),
      'Bad Header: value',
    );
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-save')));
    await tester.tap(find.byKey(const Key('isbn-source-save')));
    await tester.pump();

    expect(cubit.state, isEmpty);
    expect(find.text('isbn_data_source_invalid'), findsOneWidget);
  });

  testWidgets('edits, toggles, and deletes a source with its credential',
      (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final credentials = _CredentialsStore();
    final source = _source();
    cubit.save(source);
    await credentials.writeApiKey(source.id, 'secret');
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IsbnSourceCredentialsStore>.value(
            value: credentials,
          ),
          RepositoryProvider<CustomIsbnLookupService>.value(
            value: _LookupService(),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: _app(child: const IsbnDataSourcesScreen()),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(cubit.state.single.enabled, isFalse);

    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    tile.onTap!();
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-name')));
    await tester.enterText(find.byKey(const Key('isbn-source-name')), 'Edited');
    await _scrollUntilVisible(tester, find.byKey(const Key('isbn-source-save')));
    expect(find.byKey(const Key('isbn-source-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('isbn-source-save')));
    await tester.pumpAndSettle();
    expect(cubit.state.single.name, 'Edited');

    await tester.tap(find.byKey(const Key('isbn-source-delete-source')));
    await tester.pump();
    expect(cubit.state, isEmpty);
    expect(await credentials.readApiKey(source.id), isNull);
  });
}

Widget _app({required Widget child}) => MaterialApp(home: child);

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

IsbnDataSource _source({String id = 'source', String name = 'Example'}) =>
    IsbnDataSource(
      id: id,
      name: name,
      enabled: true,
      method: IsbnRequestMethod.get,
      urlTemplate: 'https://books.example/{isbn}',
      titleJsonPath: r'$.title',
    );

class _CredentialsStore implements IsbnSourceCredentialsStore {
  final values = <String, String>{};

  @override
  Future<void> deleteApiKey(String sourceId) async => values.remove(sourceId);

  @override
  Future<String?> readApiKey(String sourceId) async => values[sourceId];

  @override
  Future<void> writeApiKey(String sourceId, String apiKey) async {
    values[sourceId] = apiKey;
  }
}

class _LookupService extends CustomIsbnLookupService {
  _LookupService()
      : super(client: _NoopClient(), credentialsStore: _CredentialsStore());

  String? apiKeyOverride;

  @override
  Future<IsbnLookupResult?> lookup({
    required String isbn,
    required List<IsbnDataSource> sources,
    String? apiKeyOverride,
    bool useApiKeyOverride = false,
  }) async {
    this.apiKeyOverride = apiKeyOverride;
    return const IsbnLookupResult(
      title: 'Preview title',
      providerName: 'Example',
    );
  }
}

class _ThrowingLookupService extends CustomIsbnLookupService {
  _ThrowingLookupService()
      : super(client: _NoopClient(), credentialsStore: _CredentialsStore());

  @override
  Future<IsbnLookupResult?> lookup({
    required String isbn,
    required List<IsbnDataSource> sources,
    String? apiKeyOverride,
    bool useApiKeyOverride = false,
  }) => throw StateError('private request failure');
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}
