import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/model/isbn_data_source.dart';
import '../../test_helpers/in_memory_storage.dart';

final firstSource = IsbnDataSource(
  id: 'first',
  name: 'First',
  enabled: true,
  method: IsbnRequestMethod.get,
  urlTemplate: 'https://example.com/{isbn}',
  titleJsonPath: r'$.title',
);

final secondSource = IsbnDataSource(
  id: 'second',
  name: 'Second',
  enabled: true,
  method: IsbnRequestMethod.get,
  urlTemplate: 'https://example.org/{isbn}',
  titleJsonPath: r'$.title',
);

void main() {
  group('IsbnDataSourcesCubit', () {
    setUp(() {
      HydratedBloc.storage = InMemoryStorage();
    });

    tearDown(() async {
      await HydratedBloc.storage.clear();
    });

    test('saves a source and replaces it when the ID already exists', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      cubit.save(firstSource);
      cubit.save(firstSource.copyWith(name: 'Renamed'));

      expect(cubit.state, hasLength(1));
      expect(cubit.state.single.name, 'Renamed');
    });

    test('disables a saved source', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      cubit.save(firstSource);
      cubit.setEnabled(firstSource.id, false);

      expect(cubit.state.single.enabled, isFalse);
    });

    test('removes a saved source', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      cubit.save(firstSource);
      cubit.remove(firstSource.id);

      expect(cubit.state, isEmpty);
    });

    test('reorders saved sources using ReorderableListView indexes', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      cubit.save(firstSource);
      cubit.save(secondSource);
      cubit.reorder(0, 2);

      expect(cubit.state.map((source) => source.id), ['second', 'first']);
    });

    test('serializes and restores the ordered source list', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      final json = cubit.toJson([firstSource, secondSource]);
      final restored = cubit.fromJson(json!);

      expect(restored!.map((source) => source.id), ['first', 'second']);
    });

    test('skips malformed persisted sources while restoring valid sources', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      final restored = cubit.fromJson({
        'isbn_data_sources': [
          firstSource.toJson(),
          {'id': 'broken'},
          secondSource.toJson(),
        ],
      });

      expect(restored!.map((source) => source.id), ['first', 'second']);
    });

    test('skips invalid persisted sources while restoring valid neighbors', () {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      final restored = cubit.fromJson({
        'isbn_data_sources': [
          firstSource.toJson(),
          {
            ...firstSource.toJson(),
            'id': 'insecure',
            'url_template': 'http://example.com/{isbn}',
          },
          secondSource.toJson(),
        ],
      });

      expect(restored!.map((source) => source.id), ['first', 'second']);
    });
  });
}
