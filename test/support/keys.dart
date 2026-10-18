import 'package:hybrid_prefs/hybrid_prefs.dart';

const token = SecureKey<String?>('access_token');
const pin = SecureKey<int?>('pin');
const darkMode = PrefKey<bool>('dark_mode', defaultValue: false);
const name = PrefKey<String?>('name');
const count = PrefKey<int>('count', defaultValue: 0);
