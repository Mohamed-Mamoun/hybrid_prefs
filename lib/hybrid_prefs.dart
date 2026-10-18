/// Typed SharedPreferences with synchronous reads, where secure keys are
/// transparently kept in the platform's secure storage.
library;

export 'src/hybrid_prefs.dart'
    show
        DateTimeKeyCodec,
        EnumKeyCodec,
        HybridPrefs,
        JsonKeyCodec,
        KeyCodec,
        PrefKey,
        SecureKey,
        StoreKey;
export 'src/hybrid_prefs_error.dart';
export 'src/secure_store.dart';
