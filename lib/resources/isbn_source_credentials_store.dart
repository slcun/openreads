import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class IsbnSourceCredentialsStore {
  Future<String?> readApiKey(String sourceId);

  Future<void> writeApiKey(String sourceId, String apiKey);

  Future<void> deleteApiKey(String sourceId);
}

class SecureIsbnSourceCredentialsStore implements IsbnSourceCredentialsStore {
  SecureIsbnSourceCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'isbn_source_api_key_';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readApiKey(String sourceId) => _storage.read(
        key: _storageKey(sourceId),
      );

  @override
  Future<void> writeApiKey(String sourceId, String apiKey) => _storage.write(
        key: _storageKey(sourceId),
        value: apiKey,
      );

  @override
  Future<void> deleteApiKey(String sourceId) => _storage.delete(
        key: _storageKey(sourceId),
      );

  String _storageKey(String sourceId) => '$_keyPrefix$sourceId';
}
