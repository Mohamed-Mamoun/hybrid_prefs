part of 'hybrid_prefs.dart';

/// A typed key: a name, a value type [T] and a default.
///
/// Declare keys once as constants:
///
/// ```dart
/// abstract final class Keys {
///   static const token = SecureKey<String?>('access_token');
///   static const darkMode = PrefKey<bool>('dark_mode', defaultValue: false);
/// }
/// ```
///
/// A key whose [T] is non-nullable needs a [defaultValue]. Leaving it out of
/// a `const` key is a compile-time error.
///
/// `String`, `bool`, `int`, `double` and `List<String>` work out of the box.
/// Any other type needs a [codec].
sealed class StoreKey<T> {
  const StoreKey(this.name, {this.defaultValue, this.codec})
      : assert(
          defaultValue != null || null is T,
          'A key with a non-nullable type needs a defaultValue. '
          'Pass one, or make the type nullable.',
        );

  /// The storage name.
  final String name;

  /// Returned when the key has no value, or its stored value can't be read.
  final T? defaultValue;

  /// Converts values to and from the stored String. Required for types other
  /// than `String`, `bool`, `int`, `double` and `List<String>`.
  final KeyCodec<T>? codec;

  T get _default => defaultValue as T;

  bool _accepts(Object? value) => value is T;

  bool _isType<S>() => T == S || T == _typeOf<S?>();

  /// Whether values are stored as one of SharedPreferences' native types.
  bool get _isNative =>
      codec == null &&
      (_isType<String>() ||
          _isType<bool>() ||
          _isType<int>() ||
          _isType<double>() ||
          _isType<List<String>>());

  /// The codec that turns values into Strings, explicit or built in.
  KeyCodec<T> get _stringCodec {
    final codec = this.codec;
    if (codec != null) return codec;
    final KeyCodec<Object?>? builtIn = _isType<String>()
        ? const _StringCodec()
        : _isType<bool>()
            ? const _BoolCodec()
            : _isType<int>()
                ? const _IntCodec()
                : _isType<double>()
                    ? const _DoubleCodec()
                    : _isType<List<String>>()
                        ? const _StringListCodec()
                        : null;
    if (builtIn == null) throw _unsupported();
    return builtIn as KeyCodec<T>;
  }

  UnsupportedError _unsupported() => UnsupportedError(
        'Key "$name" has type $T, which needs a codec. '
        'Pass one with `codec:`, for example JsonKeyCodec or EnumKeyCodec.',
      );

  @override
  String toString() => '$runtimeType($name)';
}

/// A key stored in plain SharedPreferences. Use it for settings and other
/// non-sensitive data.
final class PrefKey<T> extends StoreKey<T> {
  /// Creates a preferences key.
  const PrefKey(super.name, {super.defaultValue, super.codec});
}

/// A key stored in the platform's secure storage (Keychain, Keystore and so
/// on). Use it for tokens and secrets.
///
/// Every secure key must be passed to [HybridPrefs.init], which loads it into
/// memory so reads stay synchronous.
final class SecureKey<T> extends StoreKey<T> {
  /// Creates a secure key.
  const SecureKey(super.name, {super.defaultValue, super.codec});
}

Type _typeOf<X>() => X;
