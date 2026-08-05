// Közös előfeltétel-ellenőrzés az AI-funkciókhoz (chat, válaszjavaslat).
//
// Mindkettő ugyanazt a három kaput követeli meg, és ezeknek együtt kell
// mozogniuk — ha az egyik függvényben lazulna valamelyik, az csendben
// megkerülhető úttá válna a másik mellett.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export interface AiMessageContext {
  supabase: SupabaseClient;
  subject: string;
  bodyText: string;
  fromAddress: string;
  fromName: string | null;
}

/**
 * A levél betöltése az AI-funkciók számára, minden ellenőrzéssel együtt.
 * Hiba esetén kész `Response`-t ad vissza, sikeres esetben a levél adatait.
 */
export async function loadMessageForAi(
  req: Request,
  messageId: string,
): Promise<Response | AiMessageContext> {
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const jwt = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

  // A `user_id` szűrés a tulajdonjog-ellenőrzés. Idegen azonosítóra ugyanazt
  // a választ adjuk, mint nem létezőre — ne lehessen létezésre következtetni.
  const { data: message } = await supabase
    .from("taskmail_email_messages")
    .select("subject, from_address, from_name, body_text, body_html, body_fetched_at, account_id")
    .eq("id", messageId)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (!message) return json({ error: "not_found" }, 404);

  // A levél tartalma csak akkor mehet külső szolgáltatóhoz, ha a felhasználó
  // ezt az adott fiókra kifejezetten engedélyezte. Ugyanaz a kapu, amit a
  // szinkron is tiszteletben tart a kategorizálásnál.
  const { data: account } = await supabase
    .from("taskmail_email_accounts")
    .select("ai_enabled")
    .eq("id", message.account_id)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (!account) return json({ error: "not_found" }, 404);
  if (!account.ai_enabled) return json({ error: "ai_not_enabled" }, 403);

  // Az AI a teljes levélre válaszol, nem a rövid részletre — ha a törzs még
  // nincs letöltve, a kliensnek előbb azt kell kérnie.
  if (!message.body_fetched_at) return json({ error: "body_not_fetched" }, 409);

  const bodyText = (message.body_text as string | null) ??
    stripHtml((message.body_html as string | null) ?? "");

  return {
    supabase,
    subject: (message.subject as string | null) ?? "(nincs tárgy)",
    bodyText,
    fromAddress: (message.from_address as string | null) ?? "",
    fromName: (message.from_name as string | null) ?? null,
  };
}

/** Ha csak HTML változat van, abból nyerünk ki olvasható szöveget. */
function stripHtml(html: string): string {
  return html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p\s*>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * A nyers hibaszöveg tartalmazhat belső részletet (hívott URL, kulcs), ezért
 * csak naplóba kerül — a kliens rövid kódot kap.
 */
export function aiErrorResponse(scope: string, err: unknown): Response {
  console.error(`[${scope}]`, err);
  const text = String(err);
  if (/ANTHROPIC_API_KEY/i.test(text)) return json({ error: "ai_not_configured" }, 500);
  if (/rate.?limit|429|overloaded/i.test(text)) return json({ error: "ai_rate_limited" }, 429);
  return json({ error: "ai_unavailable" }, 502);
}
