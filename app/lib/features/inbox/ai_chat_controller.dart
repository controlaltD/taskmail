import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';

/// Egy üzenet az AI beszélgetésben.
class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, String> toApiJson() => {
        'role': fromUser ? 'user' : 'assistant',
        'content': text,
      };
}

class AiChatState {
  const AiChatState({
    this.turns = const [],
    this.sending = false,
    this.error,
  });

  final List<ChatTurn> turns;
  final bool sending;
  final String? error;

  AiChatState copyWith({List<ChatTurn>? turns, bool? sending, String? error}) => AiChatState(
        turns: turns ?? this.turns,
        sending: sending ?? this.sending,
        error: error,
      );
}

/// A levélhez tartozó beszélgetés. Munkamenet szintű: nem tárolódik
/// adatbázisban, és a levél bezárásakor sem marad meg — így a levél
/// tartalmán túl semmi nem gyűlik fel, amit később kezelni kellene.
class AiChatController extends StateNotifier<AiChatState> {
  AiChatController(this.messageId) : super(const AiChatState());

  final String messageId;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;

    // Az előzményt még a saját üzenet hozzáadása ELŐTT rögzítjük: a szerver
    // külön paraméterként várja az új kérdést.
    final history = state.turns.map((t) => t.toApiJson()).toList();

    state = state.copyWith(
      turns: [...state.turns, ChatTurn(fromUser: true, text: trimmed)],
      sending: true,
    );

    try {
      final response = await supabase.functions.invoke(
        'ai-email-chat',
        body: {
          'messageId': messageId,
          'userMessage': trimmed,
          'history': history,
        },
      );

      final data = response.data as Map?;
      final reply = data?['reply'] as String?;
      if (reply == null) {
        state = state.copyWith(sending: false, error: aiErrorMessage(data?['error'] as String?));
        return;
      }

      state = state.copyWith(
        turns: [...state.turns, ChatTurn(fromUser: false, text: reply)],
        sending: false,
      );
    } catch (_) {
      state = state.copyWith(sending: false, error: aiErrorMessage(null));
    }
  }

  void clearError() => state = state.copyWith(sending: state.sending);
}

/// A szerver rövid hibakódot ad vissza (a nyers hibaszöveg belső részletet
/// tartalmazhatna), ezt fordítjuk olvasható üzenetre.
String aiErrorMessage(String? code) => switch (code) {
      'ai_not_enabled' =>
        'Ehhez a fiókhoz nincs bekapcsolva az AI-feldolgozás. A Fiókok fülön engedélyezheted.',
      'body_not_fetched' => 'Előbb nyisd meg a levelet, hogy az AI lássa a tartalmát.',
      'ai_rate_limited' => 'Az AI most túlterhelt. Próbáld újra egy perc múlva.',
      'ai_not_configured' => 'Az AI szolgáltatás nincs beállítva.',
      'not_found' => 'A levél nem található.',
      _ => 'Az AI most nem elérhető. Próbáld újra.',
    };

final aiChatControllerProvider =
    StateNotifierProvider.autoDispose.family<AiChatController, AiChatState, String>(
  (ref, messageId) => AiChatController(messageId),
);

/// Kérte-e már a felhasználó a válaszjavaslatot ehhez a levélhez.
///
/// Ez a kapcsoló azért kell, mert a `quickReplyProvider` figyelése önmagában
/// elindítaná a Claude-hívást. Így viszont a javaslat csak akkor készül el,
/// ha tényleg rákattintottak — nem minden levélnyitás mellékhatásaként.
final quickReplyRequestedProvider =
    StateProvider.autoDispose.family<bool, String>((ref, messageId) => false);

/// Válaszjavaslat a megnyitott levélre — kifejezett gombnyomásra fut le,
/// nem automatikusan a levél megnyitásakor.
final quickReplyProvider =
    FutureProvider.autoDispose.family<({String subject, String bodyText}), String>(
  (ref, messageId) async {
    final response = await supabase.functions.invoke(
      'ai-quick-reply',
      body: {'messageId': messageId},
    );
    final data = response.data as Map?;
    final bodyText = data?['bodyText'] as String?;
    if (bodyText == null) {
      throw AiException(aiErrorMessage(data?['error'] as String?));
    }
    return (subject: data?['subject'] as String? ?? '', bodyText: bodyText);
  },
);

class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}
