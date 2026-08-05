import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compose_controller.dart';
import 'drafts_repository.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, this.draft = const ComposeDraft()});

  final ComposeDraft draft;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _toCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  String? _accountId;
  bool _sending = false;
  String? _error;

  /// Ennyivel az utolsó leütés után mentünk. Elég rövid ahhoz, hogy egy
  /// váratlan kilépésnél alig vesszen el valami, és elég hosszú ahhoz, hogy
  /// gépelés közben ne írjunk az adatbázisba minden betűnél.
  static const _autosaveDelay = Duration(milliseconds: 1500);

  Timer? _autosaveTimer;
  String? _draftId;
  bool _savedAsDraft = false;

  @override
  void initState() {
    super.initState();
    _toCtrl = TextEditingController(text: widget.draft.to.join(', '));
    _subjectCtrl = TextEditingController(text: widget.draft.subject);
    _bodyCtrl = TextEditingController(text: widget.draft.bodyText);
    _accountId = widget.draft.accountId;
    _draftId = widget.draft.draftId;

    for (final controller in [_toCtrl, _subjectCtrl, _bodyCtrl]) {
      controller.addListener(_scheduleAutosave);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, _saveDraft);
  }

  bool get _isEmpty =>
      _recipients.isEmpty &&
      _subjectCtrl.text.trim().isEmpty &&
      _bodyCtrl.text.trim().isEmpty;

  /// A piszkozat mentése. Üres levélből nem hozunk létre sort — csak akkor,
  /// ha van benne valami menteni való.
  Future<void> _saveDraft() async {
    if (_sending || _savedAsDraft) return;
    if (_isEmpty && _draftId == null) return;

    try {
      final id = await ref.read(draftsRepositoryProvider).save(
            draftId: _draftId,
            accountId: _accountId,
            inReplyToMessageId: widget.draft.inReplyToMessageId,
            to: _recipients,
            subject: _subjectCtrl.text.trim(),
            bodyText: _bodyCtrl.text,
          );
      if (mounted) _draftId = id;
    } catch (_) {
      // A mentés csendben elbukhat (pl. hálózat) — ettől a gépelést nem
      // szakítjuk meg, a következő ütemezett mentés újrapróbálja.
    }
  }

  /// Kilépéskor a még ki nem futott automentést azonnal végrehajtjuk, hogy az
  /// utolsó néhány leütött karakter se vesszen el.
  Future<void> _flushBeforeLeaving() async {
    _autosaveTimer?.cancel();
    await _saveDraft();
  }

  List<String> get _recipients => _toCtrl.text
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _send() async {
    final accountId = _accountId;
    if (accountId == null) {
      setState(() => _error = 'Válaszd ki, melyik fiókból küldöd.');
      return;
    }
    if (_recipients.isEmpty) {
      setState(() => _error = 'Adj meg legalább egy címzettet.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'A levél szövege üres.');
      return;
    }

    // A küldés indulásakor leállítjuk az automentést: a sikeresen elküldött
    // levélből nem szabad, hogy visszamaradjon egy "megkezdett" piszkozat.
    _autosaveTimer?.cancel();

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final sentMessageId = await ref.read(composeRepositoryProvider).send(
            accountId: accountId,
            to: _recipients,
            subject: _subjectCtrl.text.trim(),
            bodyText: _bodyCtrl.text,
            inReplyToMessageId: widget.draft.inReplyToMessageId,
          );

      _savedAsDraft = true; // innentől nincs több piszkozat-mentés
      final draftId = _draftId;
      if (draftId != null) {
        await ref.read(draftsRepositoryProvider).markSent(draftId, sentMessageId);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A levél elment. ✉️')),
        );
      }
    } catch (e) {
      setState(() => _error = e is SendException ? e.message : sendErrorMessage(null));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _discardDraft() async {
    final draftId = _draftId;
    _autosaveTimer?.cancel();
    _savedAsDraft = true; // ne mentse vissza a kilépés előtti flush

    if (draftId != null) {
      await ref.read(draftsRepositoryProvider).delete(draftId);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(sendableAccountsProvider);

    return PopScope(
      // Kilépéskor kimentjük a még ki nem futott változtatásokat — a levél
      // ne vesszen el csak azért, mert visszaléptek a szerkesztőből.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_flushBeforeLeaving());
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.draft.inReplyToMessageId != null ? 'Válasz' : 'Új levél'),
        actions: [
          if (_draftId != null)
            IconButton(
              tooltip: 'Piszkozat elvetése',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _sending ? null : _discardDraft,
            ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              tooltip: 'Küldés',
              icon: const Icon(Icons.send_rounded),
              onPressed: _send,
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Hiba: $err')),
        data: (accounts) {
          if (accounts.isEmpty) return const _NoSendableAccount();

          // Ha a válasz eredeti fiókja nem küldhet (vagy nincs megadva),
          // essünk vissza az első alkalmasra, hogy ne ragadjon üresen.
          if (_accountId == null || !accounts.any((a) => a.id == _accountId)) {
            _accountId = accounts.first.id;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (accounts.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(labelText: 'Feladó'),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(value: account.id, child: Text(account.emailAddress)),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 12),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Feladó: ${accounts.first.emailAddress}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              TextField(
                controller: _toCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Címzett',
                  helperText: 'Több cím vesszővel elválasztva',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(labelText: 'Tárgy'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                minLines: 10,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Üzenet',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Küldés'),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _NoSendableAccount extends ConsumerWidget {
  const _NoSendableAccount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccount = ref.watch(hasAnyAccountProvider).valueOrNull ?? false;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✉️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              hasAccount ? 'Egyik fiókból sem lehet küldeni' : 'Nincs összekötött postafiók',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasAccount
                  ? 'A fiókjaid csak olvasási jogot kaptak. A Fiókok fülön, '
                      'fiókonként bővítheted a jogosultságot küldésre.'
                  : 'Kösd össze a Gmail vagy Outlook fiókodat a Fiókok fülön.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
