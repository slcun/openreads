import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:openreads/model/isbn_data_source.dart';

class IsbnDataSourcesCubit extends HydratedCubit<List<IsbnDataSource>> {
  IsbnDataSourcesCubit() : super(const []);

  void save(IsbnDataSource source) {
    final index = state.indexWhere((item) => item.id == source.id);
    if (index == -1) {
      emit([...state, source]);
      return;
    }

    final updated = List<IsbnDataSource>.from(state)..[index] = source;
    emit(updated);
  }

  void remove(String id) {
    emit(state.where((source) => source.id != id).toList());
  }

  void setEnabled(String id, bool enabled) {
    emit([
      for (final source in state)
        source.id == id ? source.copyWith(enabled: enabled) : source,
    ]);
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length || newIndex < 0 ||
        newIndex > state.length) {
      return;
    }

    final reordered = List<IsbnDataSource>.from(state);
    if (oldIndex < newIndex) newIndex -= 1;
    final source = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, source);
    emit(reordered);
  }

  void reorderItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length || newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }

    final reordered = List<IsbnDataSource>.from(state);
    final source = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, source);
    emit(reordered);
  }

  @override
  List<IsbnDataSource>? fromJson(Map<String, dynamic> json) {
    final rawSources = json['isbn_data_sources'];
    if (rawSources is! List) return null;

    final sources = <IsbnDataSource>[];
    for (final source in rawSources.whereType<Map>()) {
      try {
        final parsed =
            IsbnDataSource.fromJson(Map<String, dynamic>.from(source));
        if (parsed.isValid) sources.add(parsed);
      } catch (_) {
        // Ignore individual corrupt records so one bad source cannot erase all.
      }
    }

    return sources;
  }

  @override
  Map<String, dynamic>? toJson(List<IsbnDataSource> state) => {
        'isbn_data_sources': state.map((source) => source.toJson()).toList(),
      };
}
