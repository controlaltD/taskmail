// Válaszjavaslat a megnyitott levélre.
//
// Szándékosan NEM fut le automatikusan a levél megnyitásakor: az AI panel
// azonnali javaslatai a szinkron során már kiszámolt kategóriát és
// összefoglalót használják (ingyen, azonnal), ez a függvény pedig csak
// kifejezett gombnyomásra hívódik. Így a Claude-hívás mindig tudatos
// felhasználói döntés eredménye.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL).

import { suggestQuickReply } from "../_shared/claude.ts";
import { aiErrorResponse, json, loadMessageForAi } from "../_shared/ai_request.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let messageId: string;
  try {
    const body = await req.json();
    if (typeof body.messageId !== "string" || !body.messageId) {
      return json({ error: "invalid_body" }, 400);
    }
    messageId = body.messageId;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const context = await loadMessageForAi(req, messageId);
  if (context instanceof Response) return context;

  try {
    const reply = await suggestQuickReply({
      subject: context.subject,
      bodyText: context.bodyText,
      fromAddress: context.fromAddress,
      fromName: context.fromName,
    });
    return json(reply);
  } catch (err) {
    return aiErrorResponse("ai-quick-reply", err);
  }
});
