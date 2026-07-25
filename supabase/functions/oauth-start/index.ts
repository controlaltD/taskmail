// OAuth folyamat indítása.
//
// A kliens ide szól be a saját Supabase munkamenetével; ez a függvény
// ellenőrzi a bejelentkezést, létrehoz egy egyszer felhasználható nonce-ot,
// és visszaadja a kész engedélykérő URL-t. Így a hozzáférési token nem kerül
// bele a kimenő URL-be, és a client_id-k sem a kliensbe fordítva élnek.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createState, Provider } from "../_shared/oauth_state.ts";
import { codeChallengeS256, generateCodeVerifier } from "../_shared/crypto.ts";

const GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.readonly";
const OUTLOOK_SCOPE = "offline_access Mail.Read";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function buildAuthUrl(
  provider: Provider,
  nonce: string,
  challenge: string,
  functionsBase: string,
): string {
  if (provider === "gmail") {
    return `https://accounts.google.com/o/oauth2/v2/auth?${new URLSearchParams({
      client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
      redirect_uri: `${functionsBase}/gmail-oauth-callback`,
      response_type: "code",
      access_type: "offline",
      prompt: "consent",
      scope: GMAIL_SCOPE,
      state: nonce,
      code_challenge: challenge,
      code_challenge_method: "S256",
    })}`;
  }
  return `https://login.microsoftonline.com/common/oauth2/v2.0/authorize?${new URLSearchParams({
    client_id: Deno.env.get("MICROSOFT_CLIENT_ID") ?? "",
    redirect_uri: `${functionsBase}/outlook-oauth-callback`,
    response_type: "code",
    response_mode: "query",
    scope: OUTLOOK_SCOPE,
    state: nonce,
    code_challenge: challenge,
    code_challenge_method: "S256",
  })}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // A hívó személyazonossága kizárólag az Authorization headerből jön —
  // a kliens által küldött törzsből SOHA.
  const jwt = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(jwt);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

  let provider: Provider;
  try {
    const body = await req.json();
    if (body.provider !== "gmail" && body.provider !== "outlook") {
      return json({ error: "invalid_provider" }, 400);
    }
    provider = body.provider;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  try {
    const verifier = generateCodeVerifier();
    const challenge = await codeChallengeS256(verifier);
    const nonce = await createState(supabaseAdmin, userData.user.id, provider, verifier);
    const functionsBase = `${new URL(req.url).origin}/functions/v1`;
    return json({ url: buildAuthUrl(provider, nonce, challenge, functionsBase) });
  } catch (err) {
    console.error("[oauth-start]", err);
    return json({ error: "state_creation_failed" }, 500);
  }
});
