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
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
