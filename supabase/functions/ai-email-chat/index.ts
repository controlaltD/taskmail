// Szabad kérdés-válasz a megnyitott levélről.
//
// A beszélgetés előzményét a kliens küldi minden hívásnál: a chat munkamenet
// szintű, nem tárolódik adatbázisban. Így a levél tartalmán túl semmi nem
// gyűlik fel, és nincs mit később törölni sem.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL).

import { chatAboutEmail } from "../_shared/claude.ts";
import { aiErrorResponse, json, loadMessageForAi } from "../_shared/ai_request.ts";

/** Ennél hosszabb előzményt nem fogadunk el egyetlen kérésben sem. */
const MAX_HISTORY_TURNS = 20;
const MAX_MESSAGE_CHARS = 4000;

interface HistoryTurn {
  role: "user" | "assistant";
  content: string;
}

/**
 * Az előzmény a kliensből érkezik, tehát nem megbízható: csak a várt alakú
 * elemeket engedjük tovább, és korlátozzuk a méretét — különben egyetlen
 * kéréssel tetszőlegesen nagy (és drága) Claude-hívást lehetne kiváltani.
 */
function sanitizeHistory(raw: unknown): HistoryTurn[] {
  if (!Array.isArray(raw)) return [];
  const turns: HistoryTurn[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const { role, content } = item as Record<string, unknown>;
    if (role !== "user" && role !== "assistant") continue;
    if (typeof content !== "string" || !content.trim()) continue;
    turns.push({ role, content: content.slice(0, MAX_MESSAGE_CHARS) });
  }
  return turns.slice(-MAX_HISTORY_TURNS);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let messageId: string;
  let userMessage: string;
  let history: HistoryTurn[];
  try {
    const body = await req.json();
    if (typeof body.messageId !== "string" || !body.messageId) {
      return json({ error: "invalid_body" }, 400);
    }
    if (typeof body.userMessage !== "string" || !body.userMessage.trim()) {
      return json({ error: "invalid_body" }, 400);
    }
    messageId = body.messageId;
    userMessage = body.userMessage.slice(0, MAX_MESSAGE_CHARS);
    history = sanitizeHistory(body.history);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const context = await loadMessageForAi(req, messageId);
  if (context instanceof Response) return context;

  try {
    const reply = await chatAboutEmail({
      subject: context.subject,
      bodyText: context.bodyText,
      fromAddress: context.fromAddress,
      userMessage,
      history,
    });
    return json({ reply });
  } catch (err) {
    return aiErrorResponse("ai-email-chat", err);
  }
});
