import 'package:flutter/material.dart';
import 'package:hybrid_prefs/hybrid_prefs.dart';

import 'keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await HybridPrefs.init(
    secureKeys: Keys.secure,
    // Keychain entries outlive an uninstall on iOS. Don't let a reinstalled
    // app start already signed in.
    clearSecureOnReinstall: true,
    onError: (error) => debugPrint('$error'),
  );

  runApp(DemoApp(prefs: prefs));
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.prefs});

  final HybridPrefs prefs;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  HybridPrefs get prefs => widget.prefs;

  Future<void> _update(Future<void> Function() write) async {
    await write();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Typed, synchronous reads. No FutureBuilder needed.
    final token = prefs.get(Keys.accessToken);
    final themeMode = prefs.get(Keys.themeMode);

    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        appBar: AppBar(title: const Text('hybrid_prefs')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.lock),
              title: Text(token ?? 'Signed out'),
              subtitle: const Text('access_token: secure storage'),
            ),
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Theme'),
              subtitle: const Text('theme_mode: SharedPreferences'),
              trailing: DropdownButton<ThemeMode>(
                value: themeMode,
                onChanged: (mode) =>
                    _update(() => prefs.set(Keys.themeMode, mode!)),
                items: [
                  for (final mode in ThemeMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.name)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _update(
                () => token == null
                    ? prefs.set(Keys.accessToken,
                        'tok_${DateTime.now().millisecondsSinceEpoch}')
                    : prefs.remove(Keys.accessToken),
              ),
              child: Text(token == null ? 'Sign in' : 'Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
