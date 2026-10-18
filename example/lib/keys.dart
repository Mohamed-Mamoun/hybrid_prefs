import 'package:flutter/material.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';

/// Every key the app stores, declared once.
abstract final class Keys {
  /// Kept in the Keychain / Keystore.
  static const accessToken = SecureKey<String?>('access_token');

  /// Kept in SharedPreferences, by enum name.
  static const themeMode = PrefKey<ThemeMode>(
    'theme_mode',
    defaultValue: ThemeMode.system,
    codec: EnumKeyCodec(ThemeMode.values),
  );

  /// Every secure key, for HybridPrefs.init.
  static const secure = [accessToken];
}
