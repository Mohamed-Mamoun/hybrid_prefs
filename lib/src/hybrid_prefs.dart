import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'hybrid_prefs_error.dart';
import 'secure_store.dart';

part 'key_codec.dart';
part 'store_key.dart';

/// Typed key-value storage with synchronous reads. [PrefKey]s live in
/// SharedPreferences, and [SecureKey]s live in a [SecureStore].
///
/// ```dart
/// final prefs = await HybridPrefs.init(secureKeys: [Keys.token]);
///
/// prefs.get(Keys.darkMode);              // bool, synchronous
/// await prefs.set(Keys.token, 'abc');    // goes to the Keychain / Keystore
/// ```
///
/// Secure values are loaded into memory once by [init], and any plaintext
/// value of a secure key is moved into the secure store at the same time.
class HybridPrefs {
  HybridPrefs._({
    required SharedPreferences prefs,
    required SecureStore secureStore,
    required Map<String, SecureKey<Object?>> secureKeys,
    required bool allowPlaintextFallback,
    required bool clearSecureOnReinstall,
    required HybridPrefsErrorCallback? onError,
  })  : _prefs = prefs,
        _secureStore = secureStore,
        _secureKeys = secureKeys,
        _allowPlaintextFallback = allowPlaintextFallback,
        _clearSecureOnReinstall = clearSecureOnReinstall,
        _onError = onError;

  /// Preferences key that records the app has run since it was installed.
  /// Written only when `clearSecureOnReinstall` is on.
  static const String installMarkerKey = '__hybrid_prefs.installed';

  final SharedPreferences _prefs;
  final SecureStore _secureStore;
  final Map<String, SecureKey<Object?>> _secureKeys;
  final bool _allowPlaintextFallback;
  final bool _clearSecureOnReinstall;
  final HybridPrefsErrorCallback? _onError;

  /// Decoded secure values, so reads stay synchronous.
  final Map<String, Object> _secureValues = {};

  /// Loads preferences and every secure key, and migrates any plaintext
  /// value of a secure key into the secure store.
  ///
  /// * [secureKeys]: every [SecureKey] the app uses. Using one that isn't
  ///   listed here throws a [StateError].
  /// * [secureStore]: the encrypted backend, `flutter_secure_storage` by
  ///   default.
  /// * [sharedPreferences]: an existing instance. Defaults to
  ///   [SharedPreferences.getInstance].
  /// * [allowPlaintextFallback]: when a secure write fails, store the value
  ///   in plaintext preferences instead of throwing. It moves to the secure
  ///   store on a later [init]. Off by default.
  /// * [clearSecureOnReinstall]: on the first launch after a fresh install,
  ///   delete secure values left by a previous install. The iOS Keychain
  ///   survives uninstall, while preferences do not. Off by default.
  /// * [onError]: told about every failure, including recovered ones.
  ///
  /// Failing to read or decode a secure value never makes [init] throw. The
  /// key reads as its default and the failure goes to [onError].
  static Future<HybridPrefs> init({
    Iterable<SecureKey<Object?>> secureKeys = const [],
    SecureStore secureStore = const FlutterSecureStore(),
    SharedPreferences? sharedPreferences,
    bool allowPlaintextFallback = false,
    bool clearSecureOnReinstall = false,
    HybridPrefsErrorCallback? onError,
  }) async {
    final byName = <String, SecureKey<Object?>>{};
    for (final key in secureKeys) {
      if (byName.containsKey(key.name)) {
        throw ArgumentError.value(
            key.name, 'secureKeys', 'Two secure keys share this name');
      }
      if (key.name == installMarkerKey) {
        throw ArgumentError.value(key.name, 'secureKeys', 'Reserved name');
      }
      key._stringCodec; // Throws early for a type without a codec.
      byName[key.name] = key;
    }

    final hybrid = HybridPrefs._(
      prefs: sharedPreferences ?? await SharedPreferences.getInstance(),
      secureStore: secureStore,
      secureKeys: byName,
      allowPlaintextFallback: allowPlaintextFallback,
      clearSecureOnReinstall: clearSecureOnReinstall,
      onError: onError,
    );
    if (clearSecureOnReinstall) await hybrid._handleReinstall();
    await Future.wait(byName.values.map(hybrid._loadSecureKey));
    return hybrid;
  }

  /// Wipes secure values left over from an earlier install. Preferences that
  /// are completely empty and missing the marker mean a fresh install.
  /// Preferences with data but no marker mean an existing install that just
  /// turned this option on, so nothing is deleted.
  Future<void> _handleReinstall() async {
    if (_prefs.containsKey(installMarkerKey)) return;
    if (_prefs.getKeys().isEmpty) {
      for (final name in _secureKeys.keys) {
        try {
          await _secureStore.delete(name);
        } catch (error, stackTrace) {
          _report(name, HybridPrefsErrorKind.secureDelete, error, stackTrace);
        }
      }
    }
    await _prefs.setBool(installMarkerKey, true);
  }

  Future<void> _loadSecureKey(SecureKey<Object?> key) async {
    final name = key.name;

    // A plaintext copy only exists from a legacy install or a fallback write,
    // so it is always at least as new as the secure one.
    if (_prefs.containsKey(name)) {
      final Object value;
      final String encoded;
      try {
        final raw = _prefs.get(name) is List
            ? _prefs.getStringList(name)
            : _prefs.get(name);
        // A String is the encoded form from a fallback write, or a legacy
        // String value. Anything else is a legacy native value of the type.
        if (raw is String) {
          value = key._stringCodec.decode(raw) as Object;
          encoded = raw;
        } else if (raw != null && key._accepts(raw)) {
          value = raw;
          encoded = key._stringCodec.encode(raw);
        } else {
          throw FormatException('Stored ${raw.runtimeType} is not ${key.name}');
        }
      } catch (error, stackTrace) {
        _report(name, HybridPrefsErrorKind.decode, error, stackTrace);
        return;
      }
      _secureValues[name] = value;
      try {
        await _secureStore.write(name, encoded);
        await _prefs.remove(name);
      } catch (error, stackTrace) {
        // The value stays in plaintext, where it already was, and the move
        // is retried on the next init.
        _report(name, HybridPrefsErrorKind.secureWrite, error, stackTrace);
      }
      return;
    }

    final String? encoded;
    try {
      encoded = await _secureStore.read(name);
    } catch (error, stackTrace) {
      _report(name, HybridPrefsErrorKind.secureRead, error, stackTrace);
      return;
    }
    if (encoded == null) return;
    try {
      _secureValues[name] = key._stringCodec.decode(encoded) as Object;
    } catch (error, stackTrace) {
      _report(name, HybridPrefsErrorKind.decode, error, stackTrace);
    }
  }

  /// The value of [key], or its default when it has none.
  ///
  /// A stored value that can't be read as [T] also returns the default, and
  /// the failure goes to `onError`.
  T get<T>(StoreKey<T> key) => switch (key) {
        SecureKey<T>() => _getSecure(key),
        PrefKey<T>() => _getPref(key),
      };

  /// Stores [value] under [key]. Storing `null` removes the key.
  ///
  /// The new value is readable straight away, before the returned future
  /// completes. If a secure write fails and plaintext fallback is off, the
  /// previous value is restored and the error is rethrown.
  ///
  /// Throws an [ArgumentError] if [value] isn't of the key's type.
  Future<void> set<T>(StoreKey<T> key, T value) async {
    if (value == null) return remove(key);
    if (!key._accepts(value)) {
      throw ArgumentError.value(value, 'value',
          '${value.runtimeType} is not the type of ${key.runtimeType}');
    }
    switch (key) {
      case SecureKey<T>():
        await _setSecure(key, value);
      case PrefKey<T>():
        await _setPref(key, value);
    }
  }

  /// Whether [key] has a stored value.
  bool containsKey(StoreKey<Object?> key) => switch (key) {
        SecureKey() => _secureValues.containsKey(_registered(key).name),
        PrefKey() => _prefs.containsKey(_plainName(key)),
      };

  /// Names of every key with a stored value.
  Set<String> getKeys() => {
        ..._prefs
            .getKeys()
            .where((k) => k != installMarkerKey && !_secureKeys.containsKey(k)),
        ..._secureValues.keys,
      };

  /// Removes [key]'s value from wherever it is stored.
  ///
  /// For a secure key the value is gone from memory at once. If deleting it
  /// from the secure store fails, the error is rethrown.
  Future<void> remove(StoreKey<Object?> key) async {
    switch (key) {
      case PrefKey():
        await _prefs.remove(_plainName(key));
      case SecureKey():
        final name = _registered(key).name;
        _secureValues.remove(name);
        await _prefs.remove(name);
        try {
          await _secureStore.delete(name);
        } catch (error, stackTrace) {
          _report(name, HybridPrefsErrorKind.secureDelete, error, stackTrace);
          rethrow;
        }
    }
  }

  /// Removes every preference and every registered secure key.
  ///
  /// Other entries in the secure store, ones this instance doesn't manage,
  /// are left alone. If a secure delete fails, the rest are still attempted
  /// and the first error is rethrown at the end.
  Future<void> clear() async {
    _secureValues.clear();
    await _prefs.clear();
    if (_clearSecureOnReinstall) await _prefs.setBool(installMarkerKey, true);

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final name in _secureKeys.keys) {
      try {
        await _secureStore.delete(name);
      } catch (error, stackTrace) {
        _report(name, HybridPrefsErrorKind.secureDelete, error, stackTrace);
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  T _getSecure<T>(SecureKey<T> key) {
    final value = _secureValues[_registered(key).name];
    return value == null ? key._default : value as T;
  }

  Future<void> _setSecure<T>(SecureKey<T> key, T value) async {
    final name = _registered(key).name;
    final encoded = key._stringCodec.encode(value);
    final previous = _secureValues[name];
    _secureValues[name] = value as Object;
    try {
      await _secureStore.write(name, encoded);
    } catch (error, stackTrace) {
      _report(name, HybridPrefsErrorKind.secureWrite, error, stackTrace);
      if (_allowPlaintextFallback) {
        await _prefs.setString(name, encoded);
        return;
      }
      // Roll back, unless a newer write already replaced this value.
      if (identical(_secureValues[name], value)) {
        if (previous == null) {
          _secureValues.remove(name);
        } else {
          _secureValues[name] = previous;
        }
      }
      rethrow;
    }
    // Drop any plaintext copy left by an earlier fallback write.
    if (_prefs.containsKey(name)) await _prefs.remove(name);
  }

  T _getPref<T>(PrefKey<T> key) {
    final name = _plainName(key);
    try {
      final raw = key._isType<List<String>>()
          ? _prefs.getStringList(name)
          : _prefs.get(name);
      if (raw == null) return key._default;
      if (!key._isNative) {
        if (raw is! String) {
          throw FormatException('Expected an encoded String', raw);
        }
        return key._stringCodec.decode(raw);
      }
      // Web can hand back a whole double as an int.
      if (raw is int && key._isType<double>()) return raw.toDouble() as T;
      if (key._accepts(raw)) return raw as T;
      throw FormatException('Stored ${raw.runtimeType} is not $T');
    } catch (error, stackTrace) {
      _report(name, HybridPrefsErrorKind.decode, error, stackTrace);
      return key._default;
    }
  }

  Future<void> _setPref<T>(PrefKey<T> key, T value) async {
    final name = _plainName(key);
    if (!key._isNative) {
      await _prefs.setString(name, key._stringCodec.encode(value));
      return;
    }
    switch (value) {
      case final String v:
        await _prefs.setString(name, v);
      case final bool v:
        await _prefs.setBool(name, v);
      case final int v:
        await _prefs.setInt(name, v);
      case final double v:
        await _prefs.setDouble(name, v);
      case final List<String> v:
        await _prefs.setStringList(name, v);
    }
  }

  SecureKey<Object?> _registered(SecureKey<Object?> key) {
    final registered = _secureKeys[key.name];
    if (registered == null) {
      throw StateError(
          '$key was not passed to HybridPrefs.init(secureKeys: ...).');
    }
    if (registered.runtimeType != key.runtimeType) {
      throw ArgumentError.value(
          key, 'key', 'Registered as $registered, with a different type');
    }
    return registered;
  }

  String _plainName(PrefKey<Object?> key) {
    if (key.name == installMarkerKey) {
      throw ArgumentError.value(key.name, 'key', 'Reserved name');
    }
    if (_secureKeys.containsKey(key.name)) {
      throw ArgumentError.value(key.name, 'key',
          'This name belongs to a secure key; a PrefKey would store it in plaintext');
    }
    if (!key._isNative && key.codec == null) throw key._unsupported();
    return key.name;
  }

  void _report(
    String key,
    HybridPrefsErrorKind kind,
    Object error,
    StackTrace stackTrace,
  ) =>
      _onError?.call(HybridPrefsError(key, kind, error, stackTrace));
}
