// A három elrendezési szint (telefon / tablet / desktop) ellenőrzése.
//
// A levéllista Supabase-t hív, ezért itt csak azt nézzük, MELYIK paneleket
// rakja ki az elrendezés az adott szélességen — a lista betöltési hibája nem
// befolyásolja, hogy az oldalsáv vagy az AI hasáb ott van-e.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:taskmail/features/inbox/inbox_screen.dart';
import 'package:taskmail/features/inbox/widgets/ai_panel.dart';
import 'package:taskmail/features/inbox/widgets/mail_sidebar.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: InboxScreen())),
  );
  await tester.pump();
}

/// Fiókban lévő panelt akkor sem számolunk, ha a widgetfa tartalmazza —
/// a `Drawer` csak nyitáskor jelenik meg, addig nem foglal helyet.
Finder _visibleSidebar() => find.byType(MailSidebar);
Finder _visibleAiPanel() => find.byType(AiPanel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('desktop: mindhárom hasáb egyszerre látszik', (tester) async {
    await _pumpAt(tester, const Size(1400, 900));

    expect(_visibleSidebar(), findsOneWidget);
    expect(_visibleAiPanel(), findsOneWidget);
    // Széles nézeten nincs fiók: minden a helyén van.
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('tablet: mappa-ikonsáv marad, AI panel fiókba kerül', (tester) async {
    await _pumpAt(tester, const Size(760, 1024));

    final sidebar = tester.widget<MailSidebar>(_visibleSidebar());
    expect(sidebar.iconsOnly, isTrue);

    // Az AI panel csak a fiók megnyitása után jelenik meg.
    expect(_visibleAiPanel(), findsNothing);
    await tester.tap(find.byTooltip('AI panel'));
    await tester.pumpAndSettle();
    expect(_visibleAiPanel(), findsOneWidget);
  });

  testWidgets('telefon: mindkét oldalsó panel fiókban van', (tester) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(_visibleSidebar(), findsNothing);
    expect(_visibleAiPanel(), findsNothing);

    // Mappák a bal oldali fiókból.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(_visibleSidebar(), findsOneWidget);
  });
}
