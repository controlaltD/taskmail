import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mail_folder.dart';
import 'mail_layout_controller.dart';
import 'widgets/ai_panel.dart';
import 'widgets/mail_list.dart';
import 'widgets/mail_sidebar.dart';

/// Efölött fér el egymás mellett mind a három hasáb.
const double kDesktopBreakpoint = 900;

/// Efölött van hely egy állandó mappa-ikonsávnak a lista mellett (tablet).
/// Ez alatt a mappák is fiókba költöznek (telefon).
const double kTabletBreakpoint = 600;

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(selectedFolderProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Desktop: mind a három hasáb egymás mellett, semmi nincs elrejtve.
        if (width >= kDesktopBreakpoint) {
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MailSidebar(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ListHeader(folder: folder),
                      Expanded(child: MailList(folder: folder)),
                    ],
                  ),
                ),
                const AiPanel(),
              ],
            ),
          );
        }

        // Tablet: a mappák ikonsávként a helyükön maradnak (nem kell fiókot
        // nyitni a váltáshoz), az AI panel viszont fiókból jön elő — így nem
        // szorítja két keskeny hasábra a levéllistát.
        if (width >= kTabletBreakpoint) {
          return Scaffold(
            appBar: AppBar(
              title: Text(folder.title),
              actions: [const _AiPanelButton()],
            ),
            endDrawer: const Drawer(child: AiPanel(inDrawer: true)),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MailSidebar(iconsOnly: true),
                Expanded(child: MailList(folder: folder)),
              ],
            ),
          );
        }

        // Telefon: mindkét oldalsó panel fiókban, a lista kapja a teljes
        // szélességet. A levél helyben nyílik ki, ugyanúgy, mint máshol.
        return Scaffold(
          appBar: AppBar(
            title: Text(folder.title),
            actions: [const _AiPanelButton()],
          ),
          drawer: const Drawer(child: SafeArea(child: MailSidebar())),
          endDrawer: const Drawer(child: AiPanel(inDrawer: true)),
          body: MailList(folder: folder),
        );
      },
    );
  }
}

class _AiPanelButton extends StatelessWidget {
  const _AiPanelButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'AI panel',
      icon: const Icon(Icons.auto_awesome_rounded),
      onPressed: () => Scaffold.of(context).openEndDrawer(),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.folder});

  final MailFolder folder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Text(folder.title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
