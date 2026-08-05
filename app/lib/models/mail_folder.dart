import 'email_message.dart';

/// A postafiók oldalsávján választható nézetek.
///
/// FONTOS: ezek TaskMail-oldali nézetek, nem a szolgáltató mappái. A Gmail
/// címkéket használ (egy levél többhöz is tartozhat), az Outlook mappafát
/// (egy levél pontosan egy helyen van) — a kettő egyesítése önálló feladat,
/// és a mostani szinkron is kizárólag a Bejövő mappát olvassa. Amíg az nem
/// készül el, a "mappák" itt szűrők a már beszinkronizált leveleken, plusz a
/// TaskMail saját piszkozat-/elküldött-nyilvántartása.
enum MailFolder {
  inbox,
  urgent,
  task,
  newsletter,
  other,
  drafts,
  sent,
}

extension MailFolderX on MailFolder {
  String get title => switch (this) {
        MailFolder.inbox => 'Bejövő',
        MailFolder.urgent => 'Sürgős',
        MailFolder.task => 'Teendő',
        MailFolder.newsletter => 'Hírlevél',
        MailFolder.other => 'Egyéb',
        MailFolder.drafts => 'Piszkozatok',
        MailFolder.sent => 'Elküldött',
      };

  /// Az AI-kategória szűrőkhöz tartozó `ai_category` érték, ha van ilyen.
  AiCategory? get aiCategory => switch (this) {
        MailFolder.urgent => AiCategory.urgent,
        MailFolder.task => AiCategory.task,
        MailFolder.newsletter => AiCategory.newsletter,
        MailFolder.other => AiCategory.other,
        _ => null,
      };

  /// A beérkezett levelek táblájából olvasunk-e (szemben a piszkozat/
  /// elküldött nyilvántartással, ami külön táblákban él).
  bool get readsInbox => switch (this) {
        MailFolder.drafts || MailFolder.sent => false,
        _ => true,
      };

  /// A levéllista sorrendjében a szűrők a Bejövő alá tartoznak.
  bool get isCategoryFilter => aiCategory != null;
}
