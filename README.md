# hybrid_prefs

[![pub package](https://img.shields.io/pub/v/hybrid_prefs.svg)](https://pub.dev/packages/hybrid_prefs)
[![CI](https://github.com/Mohamed-Mamoun/hybrid_prefs/actions/workflows/ci.yml/badge.svg)](https://github.com/Mohamed-Mamoun/hybrid_prefs/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Mohamed-Mamoun/hybrid_prefs/branch/main/graph/badge.svg)](https://codecov.io/gh/Mohamed-Mamoun/hybrid_prefs)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Type-safe `SharedPreferences` with synchronous reads, where your secure keys
(access tokens, refresh tokens, API secrets) live in the Keychain / Keystore
instead of plaintext, and existing plaintext values are migrated
automatically.

```dart
abstract final class Keys {
  static const token = SecureKey<String?>('access_token');
  static const darkMode = PrefKey<bool>('dark_mode', defaultValue: false);
}

final prefs = await HybridPrefs.init(secureKeys: [Keys.token]);

prefs.get(Keys.darkMode);               // bool: typed, synchronous
prefs.get(Keys.token);                  // String?: synchronous, from the Keychain
await prefs.set(Keys.token, 'abc123');  // → Keychain / Keystore
await prefs.set(Keys.darkMode, true);   // → SharedPreferences
```

## Why

Most apps start by saving their auth token in `SharedPreferences`, where it
sits in plaintext. Moving it to secure storage usually hurts in three ways:

1. **Every read becomes async.** `flutter_secure_storage` only offers
   `Future`s, so interceptors, redirects and `build` methods that read the
   token synchronously all need rewriting.
2. **Existing users get logged out.** The token is still in the old
   plaintext location, and nothing moves it.
3. **Stringly-typed keys** spread across the codebase, with typos, wrong
   types and inconsistent default values.

`hybrid_prefs` loads secure values into memory once, at startup, so reads
stay synchronous. It migrates plaintext values on the next launch, and
declares every key once, with its type, its default and where it's stored.

## Features

- **Typed keys.** `prefs.get(Keys.darkMode)` is a `bool`, not a `bool?`. A
  non-nullable key without a default doesn't compile.
- **Per-key storage.** `SecureKey` goes to the Keychain / Keystore and
  `PrefKey` to SharedPreferences, behind one API.
- **Synchronous reads** for every key, secure ones included.
- **Any type.** `String`, `bool`, `int`, `double` and `List<String>` work out
  of the box. Enums, `DateTime` and JSON objects work through built-in
  codecs, and anything else through your own `KeyCodec`.
- **Automatic migration** of plaintext values into secure storage. The
  plaintext copy is removed only after the secure write succeeds.
- **Fails safe.** A failed secure write throws and rolls back, and nothing is
  silently written in plaintext. A corrupt value reads as the default and is
  reported, instead of crashing your app.
- **Reinstall-aware.** On iOS, Keychain entries survive an uninstall.
  `clearSecureOnReinstall` stops a reinstalled app from starting already
  signed in.
- **Tested on real devices.** CI runs integration tests on an iOS Simulator
  and an Android emulator against the real Keychain and Keystore, plus
  unit tests against the minimum supported dependency versions.

## Getting started

```sh
flutter pub add hybrid_prefs
```

Follow the [`flutter_secure_storage` platform setup][fss-setup] (Android
`minSdkVersion`, macOS keychain entitlements, and so on).

## Usage

### Declare your keys

```dart
abstract final class Keys {
  // Secure: stored in the Keychain / Keystore.
  static const token = SecureKey<String?>('access_token');
  static const user = SecureKey<User?>('user', codec: JsonKeyCodec(User.fromJson));

  // Plain: stored in SharedPreferences.
  static const onboarded = PrefKey<bool>('onboarded', defaultValue: false);
  static const themeMode = PrefKey<ThemeMode>('theme_mode',
      defaultValue: ThemeMode.system, codec: EnumKeyCodec(ThemeMode.values));
  static const lastSync = PrefKey<DateTime?>('last_sync', codec: DateTimeKeyCodec());

  static const secure = [token, user];
}
```

A nullable type (`String?`) reads as `null` when unset. A non-nullable type
needs a `defaultValue`.

### Initialize once

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await HybridPrefs.init(
    secureKeys: Keys.secure,
    clearSecureOnReinstall: true,
    onError: (error) => crashReporter.record(error.error, error.stackTrace,
        reason: error.toString()),
  );

  runApp(MyApp(prefs: prefs));
}
```

Every `SecureKey` must be passed to `init`, which loads it so reads can be
synchronous. Using one that isn't registered throws a `StateError`.

### Read and write

```dart
final token = prefs.get(Keys.token);        // String?
final mode = prefs.get(Keys.themeMode);     // ThemeMode

await prefs.set(Keys.token, newToken);
await prefs.set(Keys.token, null);          // same as remove
await prefs.remove(Keys.user);
await prefs.clear();                        // sign out: everything this instance manages

prefs.containsKey(Keys.onboarded);
prefs.getKeys();                            // names of keys with a stored value
```

### Options

| Option | Default | What it does |
| --- | --- | --- |
| `secureKeys` | `[]` | Every `SecureKey` the app uses. |
| `secureStore` | `FlutterSecureStore()` | The encrypted backend. Pass `FlutterSecureStore(FlutterSecureStorage(iOptions: …))` to configure it. |
| `sharedPreferences` | `SharedPreferences.getInstance()` | Use an existing instance. |
| `allowPlaintextFallback` | `false` | If a secure write fails, store the value in plaintext instead of throwing. It moves to secure storage on a later launch. |
| `clearSecureOnReinstall` | `false` | On the first launch after a fresh install, delete secure values left by a previous install. |
| `onError` | `null` | Receives every `HybridPrefsError` (`secureRead`, `secureWrite`, `secureDelete`, `decode`), including recovered ones. |

### Custom types

```dart
class DurationCodec extends KeyCodec<Duration> {
  const DurationCodec();
  @override
  String encode(Duration value) => '${value.inMilliseconds}';
  @override
  Duration decode(String encoded) => Duration(milliseconds: int.parse(encoded));
}

static const timeout = PrefKey<Duration>('timeout',
    defaultValue: Duration(seconds: 30), codec: DurationCodec());
```

If `decode` throws, the key reads as its default and the failure is reported
as `HybridPrefsErrorKind.decode`.

## How it behaves

**At startup (`init`)**, for each secure key:

- If preferences hold a value for it, from an older app version or a fallback
  write, that value is written to secure storage and then removed from
  preferences. If the secure write fails, the value stays where it was, still
  readable, and the move is retried on the next launch.
- Otherwise, the value is read from secure storage. If reading or decoding
  fails, the key reads as its default and the failure goes to `onError`.
  `init` never throws for this.

**Writes** update memory at once, like `SharedPreferences`, then persist. If
the secure write fails, the old value is restored and the error is rethrown,
or with `allowPlaintextFallback` the value goes to preferences instead.

**`remove`** clears the in-memory value at once and rethrows if the secure
delete fails, so a failed sign-out isn't silent.

**Safety checks.** A `PrefKey` can't use the name of a registered
`SecureKey`, so a secret can't leak into plaintext through a second key.
Duplicate secure names, and a secure key type without a codec, are rejected
by `init`.

**`clearSecureOnReinstall`** treats completely empty preferences without its
marker key as a fresh install. Preferences that hold data but no marker
belong to an existing install that just turned the option on, so nothing is
wiped. One edge case: an existing install whose only stored values were
secure keys looks like a fresh install the first time, and is signed out once.

## Migrating from `SharedPreferences`

Give each existing key the same name and type it already uses:

```diff
- final prefs = await SharedPreferences.getInstance();
- final token = prefs.getString('access_token');
+ // Declared in your Keys class:
+ //   static const token = SecureKey<String?>('access_token');
+ final prefs = await HybridPrefs.init(secureKeys: [Keys.token]);
+ final token = prefs.get(Keys.token);
```

Users who upgrade keep their session. Their token moves from plaintext into
the Keychain / Keystore on the first launch of the new version.

## Testing

Pass an in-memory `SecureStore`:

```dart
class MemorySecureStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

SharedPreferences.setMockInitialValues({});
final prefs = await HybridPrefs.init(
  secureKeys: Keys.secure,
  secureStore: MemorySecureStore(),
);
```

## Notes

- Secure values are held in memory for the life of the instance, which is
  what makes synchronous reads possible. Any code running in your process
  can already read them once loaded, so this doesn't change the threat
  model. It does mean secure storage is read once, at `init`.
- Create one instance and share it. Two instances keep separate in-memory
  copies.
- Dart can't fully type-check `set` when a key is upcast to
  `StoreKey<Object?>`, so values are also checked at runtime. A wrong type
  throws an `ArgumentError` instead of being stored.
- On web, `flutter_secure_storage` encrypts with a key kept in the browser,
  which is weaker protection than the Keychain or Keystore.

[fss-setup]: https://pub.dev/packages/flutter_secure_storage
