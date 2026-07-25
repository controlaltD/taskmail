/// Build-time konfiguráció, `--dart-define` értékekből.
///
/// Futtatás példa:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Ugyanaz a Supabase projekt (URL + anon key), mint a `serveos`/`serveos_admin`
/// appok esetében — ez adja a közös ServeOS auth-ot.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const microsoftClientId = String.fromEnvironment('MICROSOFT_CLIENT_ID');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
