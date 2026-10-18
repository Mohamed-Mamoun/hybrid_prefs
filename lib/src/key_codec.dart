part of 'hybrid_prefs.dart';

/// Converts values of type [T] to and from the String they are stored as.
///
/// Implement it for your own types, and keep the constructor `const` so keys
/// using the codec can be `const` too.
abstract class KeyCodec<T> {
  /// Const constructor for subclasses.
  const KeyCodec();

  /// Converts [value] to its stored form.
  String encode(T value);

  /// Converts a stored String back to a value. Throw if [encoded] is invalid.
  /// The key then reads as its default and the error is reported.
  T decode(String encoded);
}

/// Stores objects as JSON, through their `toJson()` method and a `fromJson`
/// constructor.
///
/// ```dart
/// static const user = SecureKey<User?>('user', codec: JsonKeyCodec(User.fromJson));
/// ```
final class JsonKeyCodec<T> extends KeyCodec<T> {
  /// Decodes with [fromJson]. Encoding calls the value's `toJson()`.
  const JsonKeyCodec(this.fromJson);

  /// Builds a value from its decoded JSON map.
  final T Function(Map<String, dynamic> json) fromJson;

  @override
  String encode(T value) => jsonEncode(value);

  @override
  T decode(String encoded) =>
      fromJson(jsonDecode(encoded) as Map<String, dynamic>);
}

/// Stores an enum value by its `name`, so reordering the enum is safe.
///
/// ```dart
/// static const theme = PrefKey<ThemeMode>('theme',
///     defaultValue: ThemeMode.system, codec: EnumKeyCodec(ThemeMode.values));
/// ```
final class EnumKeyCodec<T extends Enum> extends KeyCodec<T> {
  /// Decodes names against [values].
  const EnumKeyCodec(this.values);

  /// All values of the enum, usually `MyEnum.values`.
  final List<T> values;

  @override
  String encode(T value) => value.name;

  @override
  T decode(String encoded) => values.byName(encoded);
}

/// Stores a [DateTime] as an ISO-8601 string, keeping UTC or local time.
final class DateTimeKeyCodec extends KeyCodec<DateTime> {
  /// Creates the codec.
  const DateTimeKeyCodec();

  @override
  String encode(DateTime value) => value.toIso8601String();

  @override
  DateTime decode(String encoded) => DateTime.parse(encoded);
}

final class _StringCodec extends KeyCodec<String> {
  const _StringCodec();

  @override
  String encode(String value) => value;

  @override
  String decode(String encoded) => encoded;
}

final class _BoolCodec extends KeyCodec<bool> {
  const _BoolCodec();

  @override
  String encode(bool value) => '$value';

  @override
  bool decode(String encoded) => switch (encoded) {
        'true' => true,
        'false' => false,
        _ => throw FormatException('Not a bool', encoded),
      };
}

final class _IntCodec extends KeyCodec<int> {
  const _IntCodec();

  @override
  String encode(int value) => '$value';

  @override
  int decode(String encoded) => int.parse(encoded);
}

final class _DoubleCodec extends KeyCodec<double> {
  const _DoubleCodec();

  @override
  String encode(double value) => '$value';

  @override
  double decode(String encoded) => double.parse(encoded);
}

final class _StringListCodec extends KeyCodec<List<String>> {
  const _StringListCodec();

  @override
  String encode(List<String> value) => jsonEncode(value);

  @override
  List<String> decode(String encoded) =>
      (jsonDecode(encoded) as List<dynamic>).cast<String>().toList();
}
