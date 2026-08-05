enum EmailProvider { gmail, outlook }

extension EmailProviderX on EmailProvider {
  String get dbValue => name;

  static EmailProvider fromDb(String value) =>
      EmailProvider.values.firstWhere((p) => p.dbValue == value, orElse: () => EmailProvider.gmail);

  String get label => switch (this) {
        EmailProvider.gmail => 'Gmail',
        EmailProvider.outlook => 'Outlook',
      };
}

enum SyncStatus { pending, ok, error }

extension SyncStatusX on SyncStatus {
  String get dbValue => name;

  static SyncStatus fromDb(String value) =>
      SyncStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => SyncStatus.pending);
}

/// A fiókhoz tárolt hozzáférés jogosultsági szintje. A `readonly` szintű
/// kapcsolat csak olvasni tud — küldéshez a felhasználónak újra engedélyeznie
/// kell a hozzáférést a szolgáltatónál.
enum ScopeTier { readonly, send }

extension ScopeTierX on ScopeTier {
  String get dbValue => name;

  static ScopeTier fromDb(String? value) =>
      ScopeTier.values.firstWhere((t) => t.dbValue == value, orElse: () => ScopeTier.readonly);

  bool get canSend => this == ScopeTier.send;
}

/// `taskmail_email_accounts` sor. A tokeneket a kliens SOSE látja —
/// azokat az Edge Function-ök kezelik szerver oldalon, titkosítva.
class EmailAccount {
  final String id;
  final String userId;
  final EmailProvider provider;
  final String emailAddress;
  final SyncStatus syncStatus;
  final String? syncError;
  final DateTime? lastSyncedAt;

  /// A felhasználó kifejezetten hozzájárult, hogy a levelek tartalma
  /// AI-feldolgozásra külső szolgáltatóhoz (Anthropic) kerüljön.
  final bool aiEnabled;

  /// Meddig terjed a fiókhoz kapott hozzáférés (olvasás / olvasás+küldés).
  final ScopeTier scopeTier;
  final DateTime createdAt;

  const EmailAccount({
    required this.id,
    required this.userId,
    required this.provider,
    required this.emailAddress,
    this.syncStatus = SyncStatus.pending,
    this.syncError,
    this.lastSyncedAt,
    this.aiEnabled = false,
    this.scopeTier = ScopeTier.readonly,
    required this.createdAt,
  });

  factory EmailAccount.fromJson(Map<String, dynamic> json) => EmailAccount(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        provider: EmailProviderX.fromDb(json['provider'] as String),
        emailAddress: json['email_address'] as String,
        syncStatus: SyncStatusX.fromDb(json['sync_status'] as String? ?? 'pending'),
        syncError: json['sync_error'] as String?,
        lastSyncedAt:
            json['last_synced_at'] != null ? DateTime.tryParse(json['last_synced_at'] as String) : null,
        aiEnabled: json['ai_enabled'] as bool? ?? false,
        scopeTier: ScopeTierX.fromDb(json['granted_scope_tier'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
