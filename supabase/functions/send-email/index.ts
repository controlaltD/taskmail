// Levél küldése a felhasználó összekötött postafiókjából.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL).
//
// A két szolgáltató itt tér el a legjobban: a Gmail nyers, base64url-kódolt
// MIME üzenetet vár (lásd `_shared/mime.ts`), a Microsoft Graph viszont
// strukturált JSON-t, és maga állítja össze a levelet.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ensureFreshAccessToken } from "../_shared/token_refresh.ts";
import { buildGmailRaw, validAddresses } from "../_shared/mime.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

interface SendRequest {
  accountId: string;
  to: string[];
  cc: string[];
  bcc: string[];
  subject: string;
  bodyText: string;
  inReplyToMessageId: string | null;
}

function parseRequest(body: Record<string, unknown>): SendRequest | null {
  const asList = (value: unknown): string[] =>
    Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];

  if (typeof body.accountId !== "string" || !body.accountId) return null;
  if (typeof body.bodyText !== "string") return null;

  const to = validAddresses(asList(body.to));
  if (to.length === 0) return null;

  return {
    accountId: body.accountId,
    to,
    cc: validAddresses(asList(body.cc)),
    bcc: validAddresses(asList(body.bcc)),
    subject: typeof body.subject === "string" ? body.subject : "",
    bodyText: body.bodyText,
    inReplyToMessageId:
      typeof body.inReplyToMessageId === "string" ? body.inReplyToMessageId : null,
  };
}

async function sendViaGmail(
  accessToken: string,
  raw: string,
  threadId: string | null,
): Promise<{ providerMessageId: string | null; threadId: string | null }> {
  const res = await fetch(
    "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(threadId ? { raw, threadId } : { raw }),
    },
  );
  if (!res.ok) throw new Error(`Gmail küldés sikertelen: ${await res.text()}`);
  const data = await res.json();
  return {
    providerMessageId: (data.id as string) ?? null,
    threadId: (data.threadId as string) ?? null,
  };
}

async function sendViaOutlook(
  accessToken: string,
  mail: SendRequest,
  fromAddress: string,
): Promise<{ providerMessageId: string | null; threadId: string | null }> {
  const recipients = (addresses: string[]) =>
    addresses.map((address) => ({ emailAddress: { address } }));

  const res = await fetch("https://graph.microsoft.com/v1.0/me/sendMail", {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      message: {
        subject: mail.subject,
        body: { contentType: "Text", content: mail.bodyText },
        from: { emailAddress: { address: fromAddress } },
        toRecipients: recipients(mail.to),
        ccRecipients: recipients(mail.cc),
        bccRecipients: recipients(mail.bcc),
      },
      saveToSentItems: true,
    }),
  });

  // A Graph üres 202-t ad: nincs miből azonosítót kiolvasni. Ezt tudatosan
  // elfogadjuk — a saját nyilvántartásunk az elsődleges forrás.
  if (!res.ok) throw new Error(`Outlook küldés sikertelen: ${await res.text()}`);
  return { providerMessageId: null, threadId: null };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const jwt = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

  let request: SendRequest | null;
  try {
    request = parseRequest(await req.json());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!request) return json({ error: "invalid_body" }, 400);

  // A fiók a hívóé kell legyen. Idegen azonosítóra ugyanaz a válasz megy, mint
  // nem létezőre — ne lehessen mások fiókjainak létezésére következtetni.
  const { data: account } = await supabase
    .from("taskmail_email_accounts")
    .select(
      "id, user_id, provider, email_address, granted_scope_tier, " +
        "access_token_encrypted, refresh_token_encrypted, token_expires_at",
    )
    .eq("id", request.accountId)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (!account) return json({ error: "not_found" }, 404);

  // A jogosultsági szintet itt is ellenőrizzük, nem csak a felületen: a
  // kliens letiltott gombja nem biztonsági határ.
  if (account.granted_scope_tier !== "send") {
    return json({ error: "scope_upgrade_required" }, 403);
  }

  // Válasz esetén a megválaszolt levél a hívóé kell legyen, és tőle vesszük
  // át a szál-azonosítót — a kliens által küldött értékben nem bízunk.
  let threadId: string | null = null;
  if (request.inReplyToMessageId) {
    const { data: original } = await supabase
      .from("taskmail_email_messages")
      .select("thread_id")
      .eq("id", request.inReplyToMessageId)
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (!original) return json({ error: "not_found" }, 404);
    threadId = (original.thread_id as string | null) ?? null;
  }

  try {
    const accessToken = await ensureFreshAccessToken(supabase, account);
    if (!accessToken) return json({ error: "account_not_connected" }, 409);

    const fromAddress = account.email_address as string;

    const result = account.provider === "gmail"
      ? await sendViaGmail(
          accessToken,
          buildGmailRaw({
            from: fromAddress,
            to: request.to,
            cc: request.cc,
            bcc: request.bcc,
            subject: request.subject,
            bodyText: request.bodyText,
          }),
          threadId,
        )
      : await sendViaOutlook(accessToken, request, fromAddress);

    const { data: sent } = await supabase
      .from("taskmail_sent_messages")
      .insert({
        user_id: userData.user.id,
        account_id: account.id,
        provider_message_id: result.providerMessageId,
        thread_id: result.threadId ?? threadId,
        in_reply_to_message_id: request.inReplyToMessageId,
        to_addresses: request.to,
        cc_addresses: request.cc,
        bcc_addresses: request.bcc,
        subject: request.subject,
        body_text: request.bodyText,
      })
      .select("id")
      .single();

    return json({ sentMessageId: sent?.id ?? null });
  } catch (err) {
    // A nyers hibaszöveg tartalmazhatja a hívott URL-t a benne lévő tokennel.
    console.error("[send-email]", err);
    const text = String(err);
    if (/token/i.test(text) && /(refresh|expire|invalid|revoke)/i.test(text)) {
      return json({ error: "auth_expired" }, 502);
    }
    if (/quota|rate.?limit|429/i.test(text)) return json({ error: "rate_limited" }, 429);
    return json({ error: "send_failed" }, 502);
  }
});
