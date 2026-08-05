/// `taskmail_sent_messages` sor — a TaskMail-ből küldött levelek.
///
/// Csak azt tartalmazza, amit mi magunk küldtünk: a szolgáltató saját
/// "Elküldött" mappája (pl. a Gmail webes felületéről küldött levelek) nem
/// szinkronizálódik ide.
class SentMessage {
  final String id;
  final String userId;
  final String accountId;

  /// A Gmail visszaadja az elküldött levél azonosítóját; a Microsoft Graph
  /// nem, ezért Outlook esetén `null`.
  final String? providerMessageId;
  final String? threadId;
  final List<String> toAddresses;
  final List<String> ccAddresses;
  final List<String> bccAddresses;
  final String subject;
  final String? bodyText;
  final DateTime sentAt;

  const SentMessage({
    required this.id,
    required this.userId,
    required this.accountId,
    this.providerMessageId,
    this.threadId,
    this.toAddresses = const [],
    this.ccAddresses = const [],
    this.bccAddresses = const [],
    this.subject = '',
    this.bodyText,
    required this.sentAt,
  });

  static List<String> _stringList(dynamic value) =>
      (value as List?)?.map((e) => e as String).toList() ?? const [];

  factory SentMessage.fromJson(Map<String, dynamic> json) => SentMessage(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        providerMessageId: json['provider_message_id'] as String?,
        threadId: json['thread_id'] as String?,
        toAddresses: _stringList(json['to_addresses']),
        ccAddresses: _stringList(json['cc_addresses']),
        bccAddresses: _stringList(json['bcc_addresses']),
        subject: json['subject'] as String? ?? '',
        bodyText: json['body_text'] as String?,
        sentAt: DateTime.parse(json['sent_at'] as String),
      );
}
