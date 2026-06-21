import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:openreads/generated/locale_keys.g.dart';
import 'package:openreads/logic/cubit/isbn_data_sources_cubit.dart';
import 'package:openreads/model/isbn_data_source.dart';
import 'package:openreads/resources/isbn_source_credentials_store.dart';
import 'package:openreads/ui/settings_screen/isbn_data_source_editor_screen.dart';

class IsbnDataSourcesScreen extends StatelessWidget {
  const IsbnDataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(LocaleKeys.isbn_data_sources.tr())),
        floatingActionButton: FloatingActionButton(
          key: const Key('isbn-source-add'),
          onPressed: () => _openEditor(context),
          child: const Icon(Icons.add),
        ),
        body: BlocBuilder<IsbnDataSourcesCubit, List<IsbnDataSource>>(
          builder: (context, sources) {
            if (sources.isEmpty) {
              return Center(
                child: Text(LocaleKeys.isbn_data_sources_empty.tr()),
              );
            }

            return ReorderableListView.builder(
              itemCount: sources.length,
              onReorderItem: context.read<IsbnDataSourcesCubit>().reorderItem,
              itemBuilder: (context, index) {
                final source = sources[index];
                return ListTile(
                  key: ValueKey(source.id),
                  title: Text(source.name),
                  subtitle: Text(source.urlTemplate),
                  leading: Switch(
                    value: source.enabled,
                    onChanged: (enabled) => context
                        .read<IsbnDataSourcesCubit>()
                        .setEnabled(source.id, enabled),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('isbn-source-delete-${source.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: LocaleKeys.delete_book.tr(),
                        onPressed: () => _delete(context, source.id),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                  onTap: () => _openEditor(context, source),
                );
              },
            );
          },
        ),
      );

  void _openEditor(BuildContext context, [IsbnDataSource? source]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => IsbnDataSourceEditorScreen(source: source),
    ));
  }

  Future<void> _delete(BuildContext context, String sourceId) async {
    context.read<IsbnDataSourcesCubit>().remove(sourceId);
    await context
        .read<IsbnSourceCredentialsStore>()
        .deleteApiKey(sourceId);
  }
}
