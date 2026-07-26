import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/supabase/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ha a --dart-define SUPABASE_URL/SUPABASE_ANON_KEY hiányzik, a
  // Supabase kliens sosem inicializálódik, és az első képernyő (a router
  // redirect logikája) azonnal, érthetetlen kivétellel elszállna rajta —
  // ehelyett egy világos üzenetet mutatunk.
  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await initSupabase();
  runApp(const ProviderScope(child: TaskMailApp()));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_rounded, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Hiányzó konfiguráció',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A SUPABASE_URL és SUPABASE_ANON_KEY build-time értékek nincsenek '
                  'megadva. Futtasd --dart-define-vel, pl.:\n\n'
                  'flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co '
                  '--dart-define=SUPABASE_ANON_KEY=eyJ...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
