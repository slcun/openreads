import 'package:hydrated_bloc/hydrated_bloc.dart';

class InMemoryStorage implements Storage {
  final Map<String, dynamic> _values = <String, dynamic>{};

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> close() async => _values.clear();

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  dynamic read(String key) => _values[key];

  @override
  Future<void> write(String key, dynamic value) async {
    _values[key] = value;
  }
}
