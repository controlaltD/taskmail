import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

/// A ServeOS-szel közös Supabase Auth munkamenet stream-je. Ugyanaz a
/// `auth.users` forrás, mint amit a `serveos_admin` panel is használ.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabaseAuth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user ?? supabaseAuth.currentUser;
});

/// A ServeOS-felhasználóknak nincs valódi email címük/jelszavuk — csak egy
/// 4 jegyű PIN-jük, amit a ServeOS app is használ. A `pin-login` Edge
/// Function (ugyanaz, amit a ServeOS app hív) ellenőrzi a PIN-t, majd egy
/// egyszer-használatos "magic link" tokent ad vissza, amit itt valódi
/// Supabase munkamenetre váltunk — így ugyanazzal a PIN-nel, ugyanabba a
/// közös auth-ba lép be a felhasználó, mint a ServeOS-ben.
class PinLoginException implements Exception {
  const PinLoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _mapPinLoginError(String? code) => switch (code) {
      'invalid_pin' => 'Hibás PIN kód.',
      'invalid_body' => 'Érvénytelen kérés.',
      _ => 'A bejelentkezés sikertelen. Próbáld újra.',
    };

class AuthController {
  const AuthController();

  Future<void> signInWithPin(String pin, {String? venueId}) async {
    final response = await supabase.functions.invoke(
      'pin-login',
      body: {'pin': pin, 'venue_id': venueId},
    );
    final data = response.data as Map?;
    final tokenHash = data?['token_hash'] as String?;
    if (tokenHash == null) {
      throw PinLoginException(_mapPinLoginError(data?['error'] as String?));
    }
    await supabaseAuth.verifyOTP(tokenHash: tokenHash, type: OtpType.magiclink);
  }

  Future<void> signOut() async {
    await supabaseAuth.signOut();
  }
}

final authControllerProvider = Provider((ref) => const AuthController());
