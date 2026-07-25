/// AI-kategorizálás lehetséges értékei (`sync-emails` Edge Function tölti ki).
enum AiCategory { urgent, task, newsletter, other }

extension AiCategoryX on AiCategory {
  String get dbValue => name;

  static AiCategory? fromDb(String? value) {
    if (value == null) return null;
    return AiCategory.values.firstWhere((c) => c.dbValue == value, orElse: () => AiCategory.other);
  }

  String get label => switch (this) {
        AiCategory.urgent => '🔴 Sürgős',
        AiCategory.task => '✅ Teendő',
        AiCategory.newsletter => '📰 Hírlevél',
        AiCategory.other => '📩 Egyéb',
      };
}

/// `taskmail_email_messages` sor.
class EmailMessage {
  final String id;
  final String accountId;
  final String userId;
  final String? threadId;
  final String fromAddress;
  final String? fromName;
  final String subject;
  final String? snippet;
  final DateTime receivedAt;
  final AiCategory? aiCategory;
  final String? aiSummary;
  final DateTime? aiProcessedAt;
  final bool isRead;

  const EmailMessage({
    required this.id,
    required this.accountId,
    required this.userId,
    this.threadId,
    required this.fromAddress,
    this.fromName,
    required this.subject,
    this.snippet,
    required this.receivedAt,
    this.aiCategory,
    this.aiSummary,
    this.aiProcessedAt,
    this.isRead = false,
  });

  factory EmailMessage.fromJson(Map<String, dynamic> json) => EmailMessage(
        id: json['id'] as String,
        accountId: json['account_id'] as String,
        userId: json['user_id'] as String,
        threadId: json['thread_id'] as String?,
        fromAddress: json['from_address'] as String? ?? '',
        fromName: json['from_name'] as String?,
        subject: json['subject'] as String? ?? '(nincs tárgy)',
        snippet: json['snippet'] as String?,
        receivedAt: DateTime.parse(json['received_at'] as String),
        aiCategory: AiCategoryX.fromDb(json['ai_category'] as String?),
        aiSummary: json['ai_summary'] as String?,
        aiProcessedAt:
            json['ai_processed_at'] != null ? DateTime.tryParse(json['ai_processed_at'] as String) : null,
        isRead: json['is_read'] as bool? ?? false,
      );
}
