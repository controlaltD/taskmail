import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mail_folder.dart';
import 'mail_layout_controller.dart';
import 'widgets/ai_panel.dart';
import 'widgets/mail_list.dart';
import 'widgets/mail_sidebar.dart';

/// Efölött fér el egymás mellett a mappalista, a levéllista és az AI panel.
const double _threePaneBreakpoint = 900;

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(selectedFolderProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _threePaneBreakpoint;

        // Keskeny nézeten a mappalista fiókban kap helyet — a levéllista és a
        // kinyíló levéltartalom ugyanaz marad, csak a két oldalsó panel
        // költözik. Az AI panel keskenyen a következő fázisban kap saját
        // felületet.
        if (!wide) {
          return Scaffold(
            appBar: AppBar(title: Text(folder.title)),
            drawer: const Drawer(child: SafeArea(child: MailSidebar())),
            body: MailList(folder: folder),
          );
        }

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
      },
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
