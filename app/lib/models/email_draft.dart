/// `taskmail_drafts` sor — a megkezdett, még el nem küldött levél.
///
/// TaskMail-oldali: a Gmail/Outlook saját piszkozat-mappájával nem
/// szinkronizál.
class EmailDraft {
  final String id;
  final String userId;
  final String? accountId;
  final String? inReplyToMessageId;
  final List<String> toAddresses;
  final List<String> ccAddresses;
  final List<String> bccAddresses;
  final String subject;
  final String bodyText;
  final DateTime updatedAt;

  const EmailDraft({
    required this.id,
    required this.userId,
    this.accountId,
    this.inReplyToMessageId,
    this.toAddresses = const [],
    this.ccAddresses = const [],
    this.bccAddresses = const [],
    this.subject = '',
    this.bodyText = '',
    required this.updatedAt,
  });

  /// A listában megjelenő cím: tárgy, ennek híján a szöveg eleje.
  String get displayTitle {
    if (subject.trim().isNotEmpty) return subject.trim();
    final firstLine = bodyText.trim().split('\n').first.trim();
    return firstLine.isEmpty ? '(üres piszkozat)' : firstLine;
  }

  /// Üres piszkozatot nincs értelme megőrizni.
  bool get isEmpty =>
      toAddresses.isEmpty && subject.trim().isEmpty && bodyText.trim().isEmpty;

  static List<String> _stringList(dynamic value) =>
      (value as List?)?.map((e) => e as String).toList() ?? const [];

  factory EmailDraft.fromJson(Map<String, dynamic> json) => EmailDraft(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String?,
        inReplyToMessageId: json['in_reply_to_message_id'] as String?,
        toAddresses: _stringList(json['to_addresses']),
        ccAddresses: _stringList(json['cc_addresses']),
        bccAddresses: _stringList(json['bcc_addresses']),
        subject: json['subject'] as String? ?? '',
        bodyText: json['body_text'] as String? ?? '',
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
