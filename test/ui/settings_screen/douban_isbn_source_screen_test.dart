import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/ui/settings_screen/isbn_data_sources_screen.dart';
import '../../test_helpers/in_memory_storage.dart';

void main() {
  setUp(() {
    HydratedBloc.storage = InMemoryStorage();
  });

  tearDown(() async {
    await HydratedBloc.storage.clear();
  });

  testWidgets(
    'adds multiple Douban proxy sources without replacing existing ones',
    (tester) async {
      final cubit = IsbnDataSourcesCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: _app(child: const IsbnDataSourcesScreen()),
        ),
      );

      await tester.tap(find.byKey(const Key('douban-source-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('douban-source-base-url')),
        'https://books.example/proxy/',
      );
      await tester.tap(find.byKey(const Key('douban-dialog-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('douban-source-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('douban-source-base-url')),
        'https://backup.example/proxy/',
      );
      await tester.tap(find.byKey(const Key('douban-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(cubit.state, hasLength(2));
      expect(cubit.state.map((source) => source.id).toSet(), hasLength(2));
      expect(
        cubit.state.last.urlTemplate,
        'https://books.example/proxy/v1/books/isbn/{isbn}',
      );
      expect(
        cubit.state.first.urlTemplate,
        'https://backup.example/proxy/v1/books/isbn/{isbn}',
      );
    },
  );

  testWidgets('rejects an invalid URL in the dialog', (tester) async {
    final cubit = IsbnDataSourcesCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: _app(child: const IsbnDataSourcesScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('douban-source-add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('douban-source-base-url')),
      'http://not-https',
    );
    await tester.tap(find.byKey(const Key('douban-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(cubit.state, isEmpty);
  });
}

Widget _app({required Widget child}) => MaterialApp(home: child);
