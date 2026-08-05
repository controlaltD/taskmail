// Egy levél teljes tartalmának letöltése — igény szerint, amikor a
// felhasználó megnyitja a levelet.
//
// MIÉRT NEM A SZINKRONBAN: a `sync-emails` 5 percenként fut, és futásonként
// akár 50 levelet dolgoz fel. Ha mindegyikhez letöltené a teljes törzset is,
// az feleslegesen terhelné a szolgáltató kvótáját (a levelek nagy részét
// senki nem nyitja meg soha), és tárolnánk is minden levelet teljes
// terjedelmében. Így viszont csak arra fizetünk, amit tényleg elolvasnak.
//
// A letöltött törzs véglegesen eltárolódik: egy beérkezett levél tartalma
// nem változik, ezért másodszor már nem kérdezzük le a szolgáltatótól.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL) — a hívó a
// saját munkamenetével szól be.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ensureFreshAccessToken } from "../_shared/token_refresh.ts";
import { fetchGmailMessageBody } from "../_shared/gmail.ts";
import { fetchOutlookMessageBody } from "../_shared/outlook.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // A hívó személyazonossága kizárólag az Authorization headerből jön.
  const jwt = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(jwt);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

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

  // A `user_id` szűrés a tulajdonjog-ellenőrzés: idegen levél azonosítójával
  // hívva ugyanazt a "nem található" választ adjuk, mint nem létező
  // azonosítóra — ne lehessen létezésre következtetni belőle.
  const { data: message } = await supabaseAdmin
    .from("taskmail_email_messages")
    .select("id, provider_message_id, body_text, body_html, body_fetched_at, to_addresses, cc_addresses, account_id")
    .eq("id", messageId)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (!message) return json({ error: "not_found" }, 404);

  // Már letöltöttük korábban — nincs miért újra terhelni a szolgáltatót.
  if (message.body_fetched_at) {
    return json({
      bodyText: message.body_text,
      bodyHtml: message.body_html,
      toAddresses: message.to_addresses ?? [],
      ccAddresses: message.cc_addresses ?? [],
    });
  }

  const { data: account } = await supabaseAdmin
    .from("taskmail_email_accounts")
    .select("id, user_id, provider, access_token_encrypted, refresh_token_encrypted, token_expires_at")
    .eq("id", message.account_id)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (!account) return json({ error: "not_found" }, 404);

  try {
    const accessToken = await ensureFreshAccessToken(supabaseAdmin, account);
    if (!accessToken) return json({ error: "account_not_connected" }, 409);

    const fetched = account.provider === "gmail"
      ? await fetchGmailMessageBody(accessToken, message.provider_message_id as string)
      : await fetchOutlookMessageBody(accessToken, message.provider_message_id as string);

    await supabaseAdmin
      .from("taskmail_email_messages")
      .update({
        body_text: fetched.bodyText,
        body_html: fetched.bodyHtml,
        to_addresses: fetched.toAddresses,
        cc_addresses: fetched.ccAddresses,
        body_fetched_at: new Date().toISOString(),
      })
      .eq("id", message.id);

    return json(fetched);
  } catch (err) {
    // A nyers hibaszöveg tartalmazhatja a hívott URL-t a benne lévő tokennel,
    // ezért csak a naplóba kerül — a kliens rövid kódot kap.
    console.error("[fetch-email-body]", err);
    const text = String(err);
    if (/token/i.test(text) && /(refresh|expire|invalid|revoke)/i.test(text)) {
      return json({ error: "auth_expired" }, 502);
    }
    return json({ error: "fetch_failed" }, 502);
  }
});
