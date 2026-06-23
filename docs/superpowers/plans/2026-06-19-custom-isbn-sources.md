# Custom ISBN Data Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Let users configure, order, and test multiple GET/POST ISBN metadata sources before the existing Open Library fallback.

**Architecture:** Persist non-secret source definitions in a hydrated Cubit and API keys in platform secure storage. A dedicated resolver expands templates, executes sources sequentially, applies RFC 9535 JSONPath mappings, and returns the first response with a non-empty mapped title. \`SearchOLScreen\` uses this resolver only for ISBN lookup; its current Open Library path remains the fallback.

**Tech Stack:** Flutter, flutter_bloc/hydrated_bloc, http, json_path, flutter_secure_storage, flutter_test.

---

## File Structure

- Create \`lib/model/isbn_data_source.dart\` — immutable source configuration and JSON serialization.
- Create \`lib/model/isbn_lookup_result.dart\` — normalized custom-source metadata.
- Create \`lib/logic/cubit/isbn_data_sources_cubit.dart\` — ordered persisted source list.
- Create \`lib/resources/isbn_source_credentials_store.dart\` — secure API-key storage.
- Create \`lib/resources/custom_isbn_lookup_service.dart\` — template expansion, HTTP, mapping, and fallback decisions.
- Create \`lib/ui/settings_screen/isbn_data_sources_screen.dart\` and \`edit_isbn_data_source_screen.dart\` — management list and source editor.
- Modify \`pubspec.yaml\`, \`lib/main.dart\`, \`settings_screen.dart\`, \`search_ol_screen.dart\`, translations, and generated locale keys.
- Create focused tests in \`test/model/\`, \`test/logic/cubit/\`, \`test/resources/\`, and \`test/ui/\`.

### Task 1: Model and persistence

**Files:**
- Create: \`lib/model/isbn_data_source.dart\`
- Create: \`lib/logic/cubit/isbn_data_sources_cubit.dart\`
- Test: \`test/model/isbn_data_source_test.dart\`
- Test: \`test/logic/cubit/isbn_data_sources_cubit_test.dart\`

- [ ] **Step 1: Write failing serialization and reorder tests.**

~~~dart
test('round-trips a source without an API key', () {
  final source = IsbnDataSource(
    id: 'juhe', name: 'Juhe', enabled: true,
    method: IsbnHttpMethod.get,
    urlTemplate: 'https://apis.juhe.cn/isbn/query?key={apiKey}&isbn={isbn}',
    titlePath: r'$.result.title',
  );
  expect(IsbnDataSource.fromJson(source.toJson()), source);
  expect(source.toJson().containsKey('apiKey'), isFalse);
});
~~~

- [ ] **Step 2: Run the tests.**

Run: \`flutter test test/model/isbn_data_source_test.dart test/logic/cubit/isbn_data_sources_cubit_test.dart\`  
Expected: fail because the model and Cubit do not exist.

- [ ] **Step 3: Implement the immutable model and hydrated Cubit.**

The model has: ID, name, enabled state, GET/POST method, URL template, headers, JSON/form POST body, timeout, optional field JSONPaths, and optional source-ID JSONPath. Validation requires an HTTPS URL, a \`{isbn}\` placeholder in URL or body, and a title path. The Cubit stores a serializable ordered list and supports save, remove, enable, and reorder.

~~~dart
class IsbnDataSourcesCubit extends HydratedCubit<List<IsbnDataSource>> {
  IsbnDataSourcesCubit() : super(const []);
  void save(IsbnDataSource source) => emit([
    for (final item in state) if (item.id != source.id) item,
    source,
  ]);
  @override Map<String, dynamic>? toJson(List<IsbnDataSource> state) =>
      {'sources': state.map((item) => item.toJson()).toList()};
}
~~~

- [ ] **Step 4: Run the tests.**

Run: \`flutter test test/model/isbn_data_source_test.dart test/logic/cubit/isbn_data_sources_cubit_test.dart\`  
Expected: PASS.

- [ ] **Step 5: Commit.**

~~~bash
git add lib/model/isbn_data_source.dart lib/logic/cubit/isbn_data_sources_cubit.dart test/model/isbn_data_source_test.dart test/logic/cubit/isbn_data_sources_cubit_test.dart
git commit -m "feat: persist custom ISBN source definitions"
~~~

### Task 2: Secure resolver

**Files:**
- Create: \`lib/model/isbn_lookup_result.dart\`
- Create: \`lib/resources/isbn_source_credentials_store.dart\`
- Create: \`lib/resources/custom_isbn_lookup_service.dart\`
- Modify: \`pubspec.yaml\`
- Test: \`test/resources/custom_isbn_lookup_service_test.dart\`

- [ ] **Step 1: Write failing resolver tests with fake HTTP and credential dependencies.**

~~~dart
test('stops at the first source with a mapped title', () async {
  final result = await service.lookup('9787544258975', [first, second]);
  expect(result?.sourceId, 'first');
  expect(requestedUris, hasLength(1));
});

test('tries the next source after an empty mapped title', () async {
  final result = await service.lookup('9787544258975', [invalid, valid]);
  expect(result?.title, 'Valid book');
});
~~~

- [ ] **Step 2: Run the resolver tests.**

Run: \`flutter test test/resources/custom_isbn_lookup_service_test.dart\`  
Expected: fail because \`CustomIsbnLookupService\` does not exist.

- [ ] **Step 3: Implement secure storage and resolver.**

Add \`json_path: ^0.9.0\` and a Flutter/Dart-compatible \`flutter_secure_storage\` release, then run \`flutter pub get\`. Store source definitions without their API keys; store each key by source ID through \`FlutterSecureStorage\`.

Inject \`http.Client\` and the credential store. Replace only \`{isbn}\` and \`{apiKey}\`, URL-encode query values, apply the configured timeout, and execute GET, JSON POST, or form POST. Parse JSON and extract mapped values with \`JsonPath(path).read(json)\`. Any transport failure, non-2xx response, invalid JSON/JSONPath, or blank mapped title returns failure for that source and continues to the next source. Do not log API keys or full sensitive URLs.

- [ ] **Step 4: Run tests.**

Run: \`flutter test test/resources/custom_isbn_lookup_service_test.dart\`  
Expected: PASS for GET, POST JSON, form POST, invalid response, timeout, JSONPath error, first-success short circuit, and fallback.

- [ ] **Step 5: Commit.**

~~~bash
git add pubspec.yaml pubspec.lock lib/model/isbn_lookup_result.dart lib/resources/isbn_source_credentials_store.dart lib/resources/custom_isbn_lookup_service.dart test/resources/custom_isbn_lookup_service_test.dart
git commit -m "feat: resolve custom ISBN metadata sources"
~~~

### Task 3: Settings screens

**Files:**
- Create: \`lib/ui/settings_screen/isbn_data_sources_screen.dart\`
- Create: \`lib/ui/settings_screen/edit_isbn_data_source_screen.dart\`
- Modify: \`lib/main.dart\`
- Modify: \`lib/ui/settings_screen/settings_screen.dart\`
- Modify: \`assets/translations/*.json\`, \`lib/generated/locale_keys.g.dart\`
- Test: \`test/ui/settings_screen/isbn_data_sources_screen_test.dart\`

- [ ] **Step 1: Write failing widget tests.**

~~~dart
testWidgets('reorders sources and opens the editor', (tester) async {
  await tester.pumpWidget(buildSettingsHarness([first, second]));
  await tester.drag(find.text('Second source'), const Offset(0, -80));
  await tester.pumpAndSettle();
  expect(cubit.state.first.name, 'Second source');
});
~~~

- [ ] **Step 2: Run the widget test.**

Run: \`flutter test test/ui/settings_screen/isbn_data_sources_screen_test.dart\`  
Expected: fail because the settings screens do not exist.

- [ ] **Step 3: Implement the list and editor.**

Add an “ISBN data sources” tile to Settings. The list uses \`ReorderableListView\`, includes enabled switches and add/edit/delete controls, and saves ordering through the Cubit. The editor validates all source configuration, stores API keys through the secure store only, and has a sample-ISBN Test action that renders mapped preview fields or a sanitised error. It must not display query values named \`key\`, \`token\`, or \`secret\`.

Register Cubit, resolver, and secure store in \`main.dart\`. Add all new keys to maintained locale JSON files and regenerate \`LocaleKeys\` with the repository’s Easy Localization generation command.

- [ ] **Step 4: Verify UI and analysis.**

Run: \`flutter test test/ui/settings_screen/isbn_data_sources_screen_test.dart && flutter analyze\`  
Expected: PASS with no analyzer diagnostics.

- [ ] **Step 5: Commit.**

~~~bash
git add lib/main.dart lib/ui/settings_screen assets/translations lib/generated/locale_keys.g.dart test/ui/settings_screen/isbn_data_sources_screen_test.dart
git commit -m "feat: add ISBN data source settings"
~~~

### Task 4: ISBN search integration

**Files:**
- Modify: \`lib/ui/search_ol_screen/search_ol_screen.dart\`
- Test: \`test/ui/search_ol_screen/isbn_lookup_test.dart\`

- [ ] **Step 1: Write failing integration tests.**

~~~dart
testWidgets('uses custom metadata before Open Library', (tester) async {
  await pumpSearch(tester, customResult: customBook, openLibraryResult: openLibraryBook);
  await tester.enterText(find.byType(TextField).first, '9787544258975');
  await tester.tap(find.text('Search'));
  expect(find.text(customBook.title), findsOneWidget);
  expect(openLibraryService.called, isFalse);
});
~~~

- [ ] **Step 2: Run the integration test.**

Run: \`flutter test test/ui/search_ol_screen/isbn_lookup_test.dart\`  
Expected: fail because \`_searchByISBN\` calls \`OpenLibraryService.getEditionByISBN\` directly.

- [ ] **Step 3: Implement resolver-first lookup.**

In \`_searchByISBN\`, normalize the scan/input value, call the resolver with the enabled Cubit sources, and map a successful result into the existing add-book flow without assigning \`olid\`. Load a custom cover URL using the app’s existing image constraints. When the resolver returns null, retain the current Open Library edition and author lookup unchanged.

- [ ] **Step 4: Run full verification.**

Run: \`flutter test test/model test/logic/cubit test/resources test/ui/search_ol_screen test/ui/settings_screen && flutter analyze && flutter build apk\`  
Expected: all tests pass, analyzer is clean, APK build exits 0.

- [ ] **Step 5: Commit.**

~~~bash
git add lib/ui/search_ol_screen/search_ol_screen.dart test/ui/search_ol_screen/isbn_lookup_test.dart
git commit -m "feat: use configured ISBN sources before Open Library"
~~~

