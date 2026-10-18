import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_store.dart';
import 'support/keys.dart';

enum Mode { light, dark, system }

class User {
  const User(this.id, this.name);

  factory User.fromJson(Map<String, dynamic> json) =>
      User(json['id'] as int, json['name'] as String);

  final int id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is User && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

const ratio = PrefKey<double>('ratio', defaultValue: 1);
const tags = PrefKey<List<String>>('tags', defaultValue: []);
const mode = PrefKey<Mode>('mode',
    defaultValue: Mode.system, codec: EnumKeyCodec(Mode.values));
const lastSync = PrefKey<DateTime?>('last_sync', codec: DateTimeKeyCodec());
const user = SecureKey<User?>('user', codec: JsonKeyCodec(User.fromJson));
const biometrics = SecureKey<bool>('biometrics', defaultValue: false);
const scopes = SecureKey<List<String>>('scopes', defaultValue: []);
const unsupported = PrefKey<Duration?>('timeout');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureStore store;
  late List<HybridPrefsError> errors;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FakeSecureStore();
    errors = [];
  });

  Future<HybridPrefs> init() => HybridPrefs.init(
        secureKeys: [token, user, biometrics, scopes],
        secureStore: store,
        onError: errors.add,
      );

  Future<Object?> raw(String key) async =>
      (await SharedPreferences.getInstance()).get(key);

  group('defaults', () {
    test('keys without a value return their default', () async {
      final prefs = await init();

      expect(prefs.get(darkMode), isFalse);
      expect(prefs.get(count), 0);
      expect(prefs.get(ratio), 1.0);
      expect(prefs.get(tags), isEmpty);
      expect(prefs.get(mode), Mode.system);
      expect(prefs.get(name), isNull);
      expect(prefs.get(biometrics), isFalse);
    });

    test('stored values replace the default', () async {
      final prefs = await init();

      await prefs.set(darkMode, true);
      await prefs.set(count, 7);

      expect(prefs.get(darkMode), isTrue);
      expect(prefs.get(count), 7);
    });
  });

  group('native pref types', () {
    test('round-trip as SharedPreferences native types', () async {
      final prefs = await init();

      await prefs.set(ratio, 0.5);
      await prefs.set(tags, ['a', 'b']);

      expect(prefs.get(ratio), 0.5);
      expect(prefs.get(tags), ['a', 'b']);
      expect(await raw('ratio'), 0.5);
      expect(await raw('tags'), ['a', 'b']);
    });

    test('a whole double stored as an int reads as a double', () async {
      SharedPreferences.setMockInitialValues({'ratio': 2});

      final prefs = await init();

      expect(prefs.get(ratio), 2.0);
    });

    test('a value of the wrong type reads as the default and is reported',
        () async {
      SharedPreferences.setMockInitialValues({'count': 'seven'});

      final prefs = await init();

      expect(prefs.get(count), 0);
      expect(errors.single.kind, HybridPrefsErrorKind.decode);
      expect(errors.single.key, 'count');
    });
  });

  group('codecs', () {
    test('EnumKeyCodec stores the name', () async {
      final prefs = await init();

      await prefs.set(mode, Mode.dark);

      expect(prefs.get(mode), Mode.dark);
      expect(await raw('mode'), 'dark');
    });

    test('an unknown enum name reads as the default and is reported', () async {
      SharedPreferences.setMockInitialValues({'mode': 'sepia'});

      final prefs = await init();

      expect(prefs.get(mode), Mode.system);
      expect(errors.single.kind, HybridPrefsErrorKind.decode);
    });

    test('DateTimeKeyCodec round-trips, keeping UTC', () async {
      final prefs = await init();
      final at = DateTime.utc(2026, 10, 18, 9, 30);

      await prefs.set(lastSync, at);

      expect(prefs.get(lastSync), at);
      expect(prefs.get(lastSync)!.isUtc, isTrue);
    });

    test('JsonKeyCodec stores objects securely as JSON', () async {
      final prefs = await init();

      await prefs.set(user, const User(1, 'Sara'));

      expect(prefs.get(user), const User(1, 'Sara'));
      expect(jsonDecode(store.values['user']!), {'id': 1, 'name': 'Sara'});
    });

    test('secure bool and List<String> use built-in codecs', () async {
      final prefs = await init();

      await prefs.set(biometrics, true);
      await prefs.set(scopes, ['read', 'write']);

      expect(store.values['biometrics'], 'true');
      expect(jsonDecode(store.values['scopes']!), ['read', 'write']);

      final next = await init();
      expect(next.get(biometrics), isTrue);
      expect(next.get(scopes), ['read', 'write']);
    });

    test('a legacy List<String> in plaintext migrates to a secure key',
        () async {
      SharedPreferences.setMockInitialValues({
        'scopes': ['read'],
      });

      final prefs = await init();

      expect(prefs.get(scopes), ['read']);
      expect(jsonDecode(store.values['scopes']!), ['read']);
      expect(await raw('scopes'), isNull);
    });
  });

  group('misuse', () {
    test('a type without a codec throws UnsupportedError', () async {
      final prefs = await init();

      expect(() => prefs.get(unsupported), throwsUnsupportedError);
      expect(
          () => prefs.set(unsupported, Duration.zero), throwsUnsupportedError);
    });

    test('a secure key without a codec is rejected by init', () async {
      expect(
        () => HybridPrefs.init(
          secureKeys: [const SecureKey<Duration?>('timeout')],
          secureStore: store,
        ),
        throwsUnsupportedError,
      );
    });

    test('an unregistered secure key throws StateError', () async {
      final prefs = await init();

      expect(() => prefs.get(pin), throwsStateError);
      expect(() => prefs.set(pin, 1), throwsStateError);
      expect(() => prefs.containsKey(pin), throwsStateError);
    });

    test('a pref key cannot reuse a secure key name', () async {
      final prefs = await init();
      const leak = PrefKey<String?>('access_token');

      expect(() => prefs.set(leak, 'oops'), throwsArgumentError);
      expect(() => prefs.get(leak), throwsArgumentError);
      expect(store.values, isEmpty);
      expect(await raw('access_token'), isNull);
    });

    test('a secure key name registered with another type is rejected',
        () async {
      final prefs = await init();

      expect(() => prefs.get(const SecureKey<int?>('access_token')),
          throwsArgumentError);
    });

    test('duplicate secure key names are rejected by init', () async {
      expect(
        () => HybridPrefs.init(
          secureKeys: [token, const SecureKey<int?>('access_token')],
          secureStore: store,
        ),
        throwsArgumentError,
      );
    });

    test('a value of the wrong type is rejected at runtime', () async {
      final prefs = await init();
      // Dart infers T = Object here, so only the runtime check catches it.
      final StoreKey<Object?> key = count;

      expect(() => prefs.set(key, 'seven'), throwsArgumentError);
      expect(await raw('count'), isNull);
    });
  });
}
