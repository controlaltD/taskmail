import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Globális Supabase kliens elérés — inicializálás a `main.dart`-ban
/// (`Supabase.initialize`) történik, ez csak kényelmi getter.
SupabaseClient get supabase => Supabase.instance.client;

GoTrueClient get supabaseAuth => supabase.auth;

Future<void> initSupabase() async {
  if (!Env.isConfigured) return;
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
}
