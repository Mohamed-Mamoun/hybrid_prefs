import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The encrypted backend that [HybridPrefs] keeps sensitive values in.
///
/// The default is [FlutterSecureStore]. Implement this to plug in another
/// store, or a fake in tests.
abstract interface class SecureStore {
  /// The value stored under [key], or `null` if there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any existing value.
  Future<void> write(String key, String value);

  /// Removes [key]. Removing a missing key is not an error.
  Future<void> delete(String key);
}

/// [SecureStore] backed by `flutter_secure_storage`: Keychain on iOS/macOS,
/// Keystore-encrypted storage on Android, and the platform equivalents on
/// Windows, Linux and web.
class FlutterSecureStore implements SecureStore {
  /// Wraps [storage]. Pass a configured [FlutterSecureStorage] to set
  /// platform options such as the iOS keychain accessibility.
  const FlutterSecureStore([this.storage = const FlutterSecureStorage()]);

  /// The underlying plugin instance.
  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
