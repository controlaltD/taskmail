// Alap smoke teszt — a témát ellenőrzi, mert a teljes app (Supabase auth
// state-tel) futtatásához valós Supabase konfiguráció (--dart-define) kell,
// ami nincs elérhető unit teszt környezetben.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:taskmail/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Teszt környezetben ne próbáljon a Google Fonts hálózatról betölteni.
  GoogleFonts.config.allowRuntimeFetching = false;

  test('AppTheme.light és .dark hiba nélkül épül fel', () {
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(AppTheme.dark.useMaterial3, isTrue);
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
