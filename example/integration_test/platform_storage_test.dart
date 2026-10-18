import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs against the real Keychain / Keystore and real SharedPreferences
/// files, with no mocks.
const token = SecureKey<String?>('it_access_token');
const pin = SecureKey<int?>('it_pin');
const launches = PrefKey<int>('it_launches', defaultValue: 0);

const keychain = FlutterSecureStorage();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefsOnDisk;

  Future<HybridPrefs> launch({bool clearSecureOnReinstall = false}) async {
    // Re-read preferences from disk, as a fresh app launch would.
    await prefsOnDisk.reload();
    return HybridPrefs.init(
      secureKeys: [token, pin],
      clearSecureOnReinstall: clearSecureOnReinstall,
      onError: (error) => fail('Unexpected $error'),
    );
  }

  setUp(() async {
    prefsOnDisk = await SharedPreferences.getInstance();
    await prefsOnDisk.clear();
    await keychain.delete(key: token.name);
    await keychain.delete(key: pin.name);
  });

  testWidgets('secure values reach the platform store, not the prefs file',
      (_) async {
    final prefs = await launch();

    await prefs.set(token, 'device-secret');
    await prefs.set(pin, 4321);
    await prefs.set(launches, 1);

    expect(await keychain.read(key: token.name), 'device-secret');
    expect(await keychain.read(key: pin.name), '4321');
    await prefsOnDisk.reload();
    expect(prefsOnDisk.getKeys(), {launches.name});
  });

  testWidgets('values survive a relaunch', (_) async {
    final first = await launch();
    await first.set(token, 'persisted');
    await first.set(launches, 3);

    final second = await launch();

    expect(second.get(token), 'persisted');
    expect(second.get(launches), 3);
  });

  testWidgets('a plaintext token from an older app version is migrated',
      (_) async {
    await prefsOnDisk.setString(token.name, 'legacy-token');

    final prefs = await launch();

    expect(prefs.get(token), 'legacy-token');
    expect(await keychain.read(key: token.name), 'legacy-token');
    await prefsOnDisk.reload();
    expect(prefsOnDisk.containsKey(token.name), isFalse);
  });

  testWidgets('a reinstall does not inherit the previous session', (_) async {
    // Prefs are empty, as after an uninstall, but the store still holds a
    // token from the previous install.
    await keychain.write(key: token.name, value: 'stale');

    final prefs = await launch(clearSecureOnReinstall: true);

    expect(prefs.get(token), isNull);
    expect(await keychain.read(key: token.name), isNull);

    await prefs.set(token, 'fresh');
    final relaunched = await launch(clearSecureOnReinstall: true);
    expect(relaunched.get(token), 'fresh');
  });

  testWidgets('remove and clear delete from the platform store', (_) async {
    final prefs = await launch();
    await prefs.set(token, 'secret');
    await prefs.set(pin, 1);

    await prefs.remove(token);
    expect(await keychain.read(key: token.name), isNull);

    await prefs.clear();
    expect(await keychain.read(key: pin.name), isNull);
  });
}
