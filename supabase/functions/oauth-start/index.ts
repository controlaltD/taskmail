// OAuth folyamat indítása.
//
// A kliens ide szól be a saját Supabase munkamenetével; ez a függvény
// ellenőrzi a bejelentkezést, létrehoz egy egyszer felhasználható nonce-ot,
// és visszaadja a kész engedélykérő URL-t. Így a hozzáférési token nem kerül
// bele a kimenő URL-be, és a client_id-k sem a kliensbe fordítva élnek.
//
// Telepítés: JWT-ellenőrzéssel (tehát --no-verify-jwt NÉLKÜL).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createState } from "../_shared/oauth_state.ts";
import { codeChallengeS256, generateCodeVerifier } from "../_shared/crypto.ts";
import { isScopeTier, type Provider, type ScopeTier, scopeFor } from "../_shared/oauth_scopes.ts";

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
  scopeTier: ScopeTier,
  loginHint: string | null,
): string {
  if (provider === "gmail") {
    const params: Record<string, string> = {
      client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
      redirect_uri: `${functionsBase}/gmail-oauth-callback`,
      response_type: "code",
      access_type: "offline",
      prompt: "consent",
      scope: scopeFor("gmail", scopeTier),
      state: nonce,
      code_challenge: challenge,
      code_challenge_method: "S256",
    };
    // Meglévő fiók jogosultság-bővítésekor a szolgáltató a megfelelő fiókot
    // ajánlja fel — enélkül a felhasználó könnyen egy másikat választ, és
    // egy új, párhuzamos kapcsolat jön létre a meglévő bővítése helyett.
    if (loginHint) params.login_hint = loginHint;
    return `https://accounts.google.com/o/oauth2/v2/auth?${new URLSearchParams(params)}`;
  }
  const params: Record<string, string> = {
    client_id: Deno.env.get("MICROSOFT_CLIENT_ID") ?? "",
    redirect_uri: `${functionsBase}/outlook-oauth-callback`,
    response_type: "code",
    response_mode: "query",
    scope: scopeFor("outlook", scopeTier),
    state: nonce,
    code_challenge: challenge,
    code_challenge_method: "S256",
  };
  if (loginHint) params.login_hint = loginHint;
  return `https://login.microsoftonline.com/common/oauth2/v2.0/authorize?${new URLSearchParams(params)}`;
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
  let scopeTier: ScopeTier;
  let loginHint: string | null;
  try {
    const body = await req.json();
    if (body.provider !== "gmail" && body.provider !== "outlook") {
      return json({ error: "invalid_provider" }, 400);
    }
    provider = body.provider;
    // Alapértelmezés a bővebb szint: új kapcsolat egy lépésben kapja meg az
    // olvasási és küldési jogot is, hogy ne kelljen később újra végigmenni a
    // szolgáltató hozzájárulási képernyőjén.
    scopeTier = isScopeTier(body.scopeTier) ? body.scopeTier : "send";
    loginHint = typeof body.loginHint === "string" && body.loginHint ? body.loginHint : null;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  try {
    const verifier = generateCodeVerifier();
    const challenge = await codeChallengeS256(verifier);
    const nonce = await createState(
      supabaseAdmin,
      userData.user.id,
      provider,
      verifier,
      scopeTier,
    );
    const functionsBase = `${new URL(req.url).origin}/functions/v1`;
    return json({
      url: buildAuthUrl(provider, nonce, challenge, functionsBase, scopeTier, loginHint),
    });
  } catch (err) {
    console.error("[oauth-start]", err);
    return json({ error: "state_creation_failed" }, 500);
  }
});
