import 'package:hybrid_prefs/hybrid_prefs.dart';

/// In-memory [SecureStore] whose operations can be made to fail.
class FakeSecureStore implements SecureStore {
  FakeSecureStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write failed');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('delete failed');
    values.remove(key);
  }
}
