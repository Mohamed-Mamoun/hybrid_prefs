import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';
import 'package:hybrid_prefs_example/keys.dart';
import 'package:hybrid_prefs_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySecureStore implements SecureStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late MemorySecureStore store;
  late HybridPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = MemorySecureStore();
    prefs = await HybridPrefs.init(secureKeys: Keys.secure, secureStore: store);
  });

  testWidgets('sign in stores the token securely, sign out removes it',
      (tester) async {
    await tester.pumpWidget(DemoApp(prefs: prefs));
    expect(find.text('Signed out'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    final token = store.values['access_token']!;
    expect(token, startsWith('tok_'));
    expect(find.text(token), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('theme mode is a plain preference stored by name',
      (tester) async {
    await tester.pumpWidget(DemoApp(prefs: prefs));

    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dark').last);
    await tester.pumpAndSettle();

    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('theme_mode'), 'dark');
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark);
  });
}
