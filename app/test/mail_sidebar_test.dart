// A mappalista nem függ Supabase-től — csak a kiválasztott mappa
// állapotától —, ezért valódi widget teszttel ellenőrizhető.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:taskmail/features/inbox/mail_layout_controller.dart';
import 'package:taskmail/features/inbox/widgets/mail_sidebar.dart';
import 'package:taskmail/models/mail_folder.dart';

Widget _harness({required Widget child}) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('nyitva minden mappa neve látszik', (tester) async {
    await tester.pumpWidget(_harness(child: const MailSidebar()));
    await tester.pumpAndSettle();

    for (final folder in MailFolder.values) {
      expect(find.text(folder.title), findsOneWidget, reason: folder.name);
    }
  });

  testWidgets('mappára kattintva a kiválasztás átvált', (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const MailSidebar();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedRef.read(selectedFolderProvider), MailFolder.inbox);

    await tester.tap(find.text(MailFolder.sent.title));
    await tester.pumpAndSettle();

    expect(capturedRef.read(selectedFolderProvider), MailFolder.sent);
  });

  testWidgets('összecsukva a nevek eltűnnek, az ikonok maradnak', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sidebarCollapsedProvider.overrideWith((ref) => true)],
        child: const MaterialApp(home: Scaffold(body: MailSidebar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(MailFolder.inbox.title), findsNothing);
    expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
  });
}
