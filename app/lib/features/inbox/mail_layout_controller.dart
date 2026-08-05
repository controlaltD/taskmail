import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mail_folder.dart';

/// A kiválasztott mappa. Riverpodban, nem widget-állapotban: az oldalsáv és a
/// levéllista testvérek a hárompaneles elrendezésben, nem szülő-gyerek
/// viszonyban, így a kiválasztást nem lehet egyszerűen lefelé továbbadni.
final selectedFolderProvider = StateProvider<MailFolder>((ref) => MailFolder.inbox);

/// Össze van-e csukva a bal oldali mappalista. Széles nézeten nyitva indul.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Össze van-e csukva a jobb oldali AI panel. A tartalma a 3. fázisban
/// készül el; addig a helye és a nyit/zár működése már a helyén van.
final aiPanelCollapsedProvider = StateProvider<bool>((ref) => false);
