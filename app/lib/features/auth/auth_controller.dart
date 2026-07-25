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

class AuthController {
  const AuthController();

  Future<void> signInWithMagicLink(String email) async {
    await supabaseAuth.signInWithOtp(email: email);
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    await supabaseAuth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await supabaseAuth.signOut();
  }
}

final authControllerProvider = Provider((ref) => const AuthController());
