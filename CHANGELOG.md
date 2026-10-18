## 1.0.0

First release.

- Typed keys: `PrefKey<T>` for SharedPreferences and `SecureKey<T>` for the
  Keychain / Keystore. A non-nullable key without a default is a
  compile-time error.
- Synchronous `get` for every key, secure ones included. Secure values are
  loaded once by `HybridPrefs.init`.
- `String`, `bool`, `int`, `double` and `List<String>` work out of the box,
  with `JsonKeyCodec`, `EnumKeyCodec`, `DateTimeKeyCodec` or your own
  `KeyCodec` for anything else.
- Automatic migration of plaintext values of secure keys. The plaintext copy
  is removed only after the secure write succeeds.
- Fails safe: failed secure writes throw and roll back unless
  `allowPlaintextFallback` is on. Unreadable values return the key's default.
- `clearSecureOnReinstall` stops iOS reinstalls from inheriting the previous
  install's Keychain entries.
- `onError` reports every secure-storage and decode failure.
- Pluggable `SecureStore` backend for tests and custom storage.
