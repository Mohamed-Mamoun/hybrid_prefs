import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_store.dart';
import 'support/keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureStore store;
  late List<HybridPrefsError> errors;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FakeSecureStore();
    errors = [];
  });

  Future<HybridPrefs> init({
    bool allowPlaintextFallback = false,
    bool clearSecureOnReinstall = false,
  }) =>
      HybridPrefs.init(
        secureKeys: [token, pin],
        secureStore: store,
        allowPlaintextFallback: allowPlaintextFallback,
        clearSecureOnReinstall: clearSecureOnReinstall,
        onError: errors.add,
      );

  Future<Map<String, Object>> plaintext() async {
    final prefs = await SharedPreferences.getInstance();
    return {for (final k in prefs.getKeys()) k: prefs.get(k)!};
  }

  group('routing', () {
    test('secure keys go to the secure store, never to preferences', () async {
      final prefs = await init();

      await prefs.set(token, 'secret');
      await prefs.set(pin, 1234);

      expect(store.values, {'access_token': 'secret', 'pin': '1234'});
      expect(await plaintext(), isEmpty);
    });

    test('pref keys go to preferences', () async {
      final prefs = await init();

      await prefs.set(darkMode, true);
      await prefs.set(name, 'Sara');

      expect(store.values, isEmpty);
      expect(await plaintext(), {'dark_mode': true, 'name': 'Sara'});
    });

    test('secure values read synchronously, even before the write completes',
        () async {
      final prefs = await init();

      final write = prefs.set(token, 'secret');
      expect(prefs.get(token), 'secret');
      await write;

      expect(prefs.containsKey(token), isTrue);
    });

    test('secure values written earlier are loaded by init', () async {
      store.values.addAll({'access_token': 'saved', 'pin': '42'});

      final prefs = await init();

      expect(prefs.get(token), 'saved');
      expect(prefs.get(pin), 42);
    });

    test('setting null removes the key', () async {
      final prefs = await init();
      await prefs.set(token, 'secret');
      await prefs.set(name, 'Sara');

      await prefs.set(token, null);
      await prefs.set(name, null);

      expect(prefs.getKeys(), isEmpty);
      expect(store.values, isEmpty);
    });

    test('getKeys and containsKey cover both stores', () async {
      final prefs = await init();
      expect(prefs.containsKey(token), isFalse);

      await prefs.set(token, 'secret');
      await prefs.set(count, 1);

      expect(prefs.getKeys(), {'access_token', 'count'});
      expect(prefs.containsKey(count), isTrue);
    });
  });

  group('migration', () {
    test('a plaintext value is moved into the secure store', () async {
      SharedPreferences.setMockInitialValues(
          {'access_token': 'legacy', 'other': 1});

      final prefs = await init();

      expect(prefs.get(token), 'legacy');
      expect(store.values, {'access_token': 'legacy'});
      expect(await plaintext(), {'other': 1});
    });

    test('a native plaintext value is encoded for the secure store', () async {
      SharedPreferences.setMockInitialValues({'pin': 1234});

      final prefs = await init();

      expect(prefs.get(pin), 1234);
      expect(store.values, {'pin': '1234'});
      expect(await plaintext(), isEmpty);
    });

    test('the plaintext value wins over an older secure value', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'newer'});
      store.values['access_token'] = 'older';

      final prefs = await init();

      expect(prefs.get(token), 'newer');
      expect(store.values['access_token'], 'newer');
    });

    test('a failed move keeps the plaintext value and retries next init',
        () async {
      SharedPreferences.setMockInitialValues({'access_token': 'legacy'});
      store.failWrites = true;

      final first = await init();

      expect(first.get(token), 'legacy');
      expect(await plaintext(), {'access_token': 'legacy'});
      expect(errors.single.kind, HybridPrefsErrorKind.secureWrite);

      store.failWrites = false;
      final second = await init();

      expect(second.get(token), 'legacy');
      expect(store.values, {'access_token': 'legacy'});
      expect(await plaintext(), isEmpty);
    });

    test('an unreadable plaintext value is reported and left alone', () async {
      SharedPreferences.setMockInitialValues({'pin': true});

      final prefs = await init();

      expect(prefs.get(pin), isNull);
      expect(errors.single.kind, HybridPrefsErrorKind.decode);
      expect(store.values, isEmpty);
      expect(await plaintext(), {'pin': true});
    });
  });

  group('secure store failures', () {
    test('a failed read at init reads as the default and is reported',
        () async {
      store.values['access_token'] = 'secret';
      store.failReads = true;

      final prefs = await init();

      expect(prefs.get(token), isNull);
      expect(errors.map((e) => e.kind),
          everyElement(HybridPrefsErrorKind.secureRead));
      expect(errors.first.toString(), contains('read failed'));
    });

    test('a corrupt secure value reads as the default and is reported',
        () async {
      store.values['pin'] = 'not a number';

      final prefs = await init();

      expect(prefs.get(pin), isNull);
      expect(errors.single.kind, HybridPrefsErrorKind.decode);
      expect(errors.single.key, 'pin');
    });

    test('a failed write throws and restores the previous value', () async {
      final prefs = await init();
      await prefs.set(token, 'first');
      store.failWrites = true;

      await expectLater(prefs.set(token, 'second'), throwsStateError);

      expect(prefs.get(token), 'first');
      expect(await plaintext(), isEmpty);
      expect(errors.single.kind, HybridPrefsErrorKind.secureWrite);
    });

    test('a failed first write throws and leaves the key empty', () async {
      final prefs = await init();
      store.failWrites = true;

      await expectLater(prefs.set(token, 'secret'), throwsStateError);

      expect(prefs.containsKey(token), isFalse);
    });

    test('with fallback, a failed write lands in plaintext and is moved later',
        () async {
      final prefs = await init(allowPlaintextFallback: true);
      store.failWrites = true;

      await prefs.set(pin, 99);

      expect(prefs.get(pin), 99);
      expect(await plaintext(), {'pin': '99'});

      store.failWrites = false;
      final next = await init(allowPlaintextFallback: true);

      expect(next.get(pin), 99);
      expect(store.values, {'pin': '99'});
      expect(await plaintext(), isEmpty);
    });

    test('a successful write removes a plaintext copy from a fallback',
        () async {
      final prefs = await init(allowPlaintextFallback: true);
      store.failWrites = true;
      await prefs.set(token, 'old');
      store.failWrites = false;

      await prefs.set(token, 'new');

      expect(store.values, {'access_token': 'new'});
      expect(await plaintext(), isEmpty);
    });

    test('a failed remove clears memory and rethrows', () async {
      final prefs = await init();
      await prefs.set(token, 'secret');
      store.failDeletes = true;

      await expectLater(prefs.remove(token), throwsStateError);

      expect(prefs.get(token), isNull);
      expect(errors.single.kind, HybridPrefsErrorKind.secureDelete);
    });
  });

  group('remove and clear', () {
    test('remove deletes a secure key from both stores', () async {
      SharedPreferences.setMockInitialValues({'keep': 1});
      final prefs = await init();
      await prefs.set(token, 'secret');

      await prefs.remove(token);

      expect(prefs.containsKey(token), isFalse);
      expect(store.values, isEmpty);
      expect(await plaintext(), {'keep': 1});
    });

    test('remove deletes a pref key', () async {
      final prefs = await init();
      await prefs.set(count, 5);

      await prefs.remove(count);

      expect(prefs.get(count), 0);
      expect(prefs.containsKey(count), isFalse);
    });

    test('clear wipes preferences and registered secure keys only', () async {
      store.values['not_managed'] = 'keep me';
      final prefs = await init();
      await prefs.set(token, 'secret');
      await prefs.set(count, 1);

      await prefs.clear();

      expect(prefs.getKeys(), isEmpty);
      expect(store.values, {'not_managed': 'keep me'});
      expect(await plaintext(), isEmpty);
    });

    test('clear attempts every key and rethrows the first failure', () async {
      final prefs = await init();
      await prefs.set(token, 'secret');
      await prefs.set(pin, 1);
      store.failDeletes = true;

      await expectLater(prefs.clear(), throwsStateError);

      expect(prefs.getKeys(), isEmpty);
      expect(errors, hasLength(2));
    });
  });

  group('clearSecureOnReinstall', () {
    test('a fresh install wipes secure values left by an earlier install',
        () async {
      store.values['access_token'] = 'from old install';

      final prefs = await init(clearSecureOnReinstall: true);

      expect(prefs.get(token), isNull);
      expect(store.values, isEmpty);
    });

    test('an existing install turning the option on keeps its values',
        () async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      store.values['access_token'] = 'still valid';

      final prefs = await init(clearSecureOnReinstall: true);

      expect(prefs.get(token), 'still valid');
    });

    test('later launches keep secure values', () async {
      final first = await init(clearSecureOnReinstall: true);
      await first.set(token, 'secret');

      final second = await init(clearSecureOnReinstall: true);

      expect(second.get(token), 'secret');
    });

    test('values set after clear survive the next launch', () async {
      final prefs = await init(clearSecureOnReinstall: true);
      await prefs.clear();
      await prefs.set(token, 'after clear');

      final next = await init(clearSecureOnReinstall: true);

      expect(next.get(token), 'after clear');
    });

    test('the install marker is hidden from getKeys', () async {
      final prefs = await init(clearSecureOnReinstall: true);

      expect(prefs.getKeys(), isEmpty);
    });

    test('is off by default', () async {
      store.values['access_token'] = 'kept';

      final prefs = await init();

      expect(prefs.get(token), 'kept');
      expect(await plaintext(), isEmpty);
    });
  });

  test('works with the default flutter_secure_storage backend', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'keychain'});

    final prefs = await HybridPrefs.init(secureKeys: [token]);
    expect(prefs.get(token), 'keychain');

    await prefs.set(token, 'updated');
    expect(await const FlutterSecureStorage().read(key: 'access_token'),
        'updated');
  });
}
