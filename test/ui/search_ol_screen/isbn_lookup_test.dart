import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:openreads/main.dart' as app;
import 'package:openreads/core/constants/enums/enums.dart';
import 'package:openreads/logic/bloc/open_library_search_bloc/open_library_search_bloc.dart';
import 'package:openreads/logic/cubit/book_cubit.dart';
import 'package:openreads/logic/cubit/current_book_cubit.dart';
import 'package:openreads/logic/cubit/default_book_status_cubit.dart';
import 'package:openreads/logic/cubit/default_book_tags_cubit.dart';
import 'package:openreads/logic/cubit/edit_book_cubit.dart';
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/model/isbn_lookup_result.dart';
import 'package:openreads/resources/custom_isbn_lookup_service.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';
import 'package:openreads/ui/search_ol_screen/search_ol_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../test_helpers/in_memory_storage.dart';

void main() {
  late Directory testDirectory;
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HydratedBloc.storage = InMemoryStorage();
    SharedPreferences.setMockInitialValues({});
    testDirectory = Directory.systemTemp.createTempSync('openreads_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getTemporaryDirectory') {
        return testDirectory.path;
      }
      return null;
    });
    app.appDocumentsDirectory = testDirectory;
    app.appTempDirectory = testDirectory;
    app.bookCubit = BookCubit();
  });

  tearDown(() async {
    await HydratedBloc.storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (testDirectory.existsSync()) {
      testDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('uses custom ISBN source result before Open Library', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final editCubit = EditBookCubit();
    final lookup = _FakeLookupService(
      const IsbnLookupResult(
        title: 'Custom Book',
        author: 'Custom Author',
        providerName: 'Test Source',
        sourceId: 'src-123',
        coverUrl: 'https://covers.example/custom.jpg',
      ),
    );
    addTearDown(cubit.close);
    addTearDown(editCubit.close);

    await tester.pumpWidget(_buildApp(
      cubit: cubit,
      lookup: lookup,
      editCubit: editCubit,
    ));

    await tester.enterText(find.byType(EditableText).first, '9780306406157');
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle();

    expect(editCubit.state.title, 'Custom Book');
    expect(editCubit.state.providerName, 'Test Source');
    expect(editCubit.state.sourceId, 'src-123');
    expect(lookup.wasCalled, isTrue);
  });

  testWidgets('falls back to Open Library when no custom source matches', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final lookup = _FakeLookupService(null);
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildApp(
      cubit: cubit,
      lookup: lookup,
    ));

    await tester.enterText(find.byType(EditableText).first, '9780306406157');
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle();

    expect(lookup.wasCalled, isTrue);
  });

  testWidgets('sets providerName and sourceId on the book from custom source', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    final editCubit = EditBookCubit();
    final lookup = _FakeLookupService(
      const IsbnLookupResult(
        title: 'Provider Book',
        author: 'Author',
        providerName: 'MyProvider',
        sourceId: 'abc-456',
      ),
    );
    addTearDown(cubit.close);
    addTearDown(editCubit.close);

    await tester.pumpWidget(_buildApp(
      cubit: cubit,
      lookup: lookup,
      editCubit: editCubit,
    ));

    await tester.enterText(find.byType(EditableText).first, '9780306406157');
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle();

    final book = editCubit.state;
    expect(book.title, 'Provider Book');
    expect(book.providerName, 'MyProvider');
    expect(book.sourceId, 'abc-456');
    expect(book.olid, isNull);
  });

  testWidgets('skips disabled sources', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    cubit.save(IsbnDataSource(
      id: 'disabled',
      name: 'Disabled',
      enabled: false,
      method: IsbnRequestMethod.get,
      urlTemplate: 'https://example.com/{isbn}',
      titleJsonPath: r'$.title',
    ));
    final lookup = _FakeLookupService(null);
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildApp(
      cubit: cubit,
      lookup: lookup,
    ));

    await tester.enterText(find.byType(EditableText).first, '9780306406157');
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle();

    expect(lookup.wasCalled, isTrue);
    expect(lookup.sourcesPassed, isEmpty);
  });
}

Widget _buildApp({
  required IsbnDataSourcesCubit cubit,
  required _FakeLookupService lookup,
  EditBookCubit? editCubit,
}) {
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<CustomIsbnLookupService>.value(value: lookup),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        if (editCubit != null)
          BlocProvider<EditBookCubit>.value(value: editCubit)
        else
          BlocProvider(create: (_) => EditBookCubit()),
        BlocProvider(create: (_) => EditBookCoverCubit()),
        BlocProvider(create: (_) => CurrentBookCubit()),
        BlocProvider(
          create: (_) => OpenLibrarySearchBloc()
            ..add(const OpenLibrarySearchSetISBN()),
        ),
        BlocProvider(create: (_) => DefaultBooksFormatCubit()),
        BlocProvider(create: (_) => DefaultBookTagsCubit()),
      ],
      child: const MaterialApp(
        home: SearchOLScreen(status: BookStatus.read),
      ),
    ),
  );
}

class _FakeLookupService extends CustomIsbnLookupService {
  _FakeLookupService(this._result)
      : super(
          client: _NoopClient(),
          credentialsStore: _NoopCredentialsStore(),
        );

  final IsbnLookupResult? _result;
  bool wasCalled = false;
  List<IsbnDataSource> sourcesPassed = [];

  @override
  Future<IsbnLookupResult?> lookup({
    required String isbn,
    required List<IsbnDataSource> sources,
    String? apiKeyOverride,
    bool useApiKeyOverride = false,
  }) async {
    wasCalled = true;
    sourcesPassed = sources.where((s) => s.enabled).toList();
    return _result;
  }
}

class _NoopClient extends Fake implements http.Client {}

class _NoopCredentialsStore implements IsbnSourceCredentialsStore {
  @override
  Future<void> deleteApiKey(String sourceId) async {}

  @override
  Future<String?> readApiKey(String sourceId) async => null;

  @override
  Future<void> writeApiKey(String sourceId, String apiKey) async {}
}
