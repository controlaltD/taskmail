// Gmail OAuth callback: Google ide irányítja vissza a usert a consent után.
// A `state` egy egyszer felhasználható nonce, amit az `oauth-start` függvény
// adott ki — ebből derül ki, melyik user fiókjához kössük az emailt. A
// code→token cserét itt végezzük (client_secret kell hozzá, ezért nem lehet
// a kliensben).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encryptToken, tokenAad } from "../_shared/crypto.ts";
import { exchangeGmailCode, fetchGmailProfile } from "../_shared/gmail.ts";
import { consumeState } from "../_shared/oauth_state.ts";

const APP_CALLBACK_SCHEME = "hu.serveos.taskmail://oauth-callback";

function redirect(status: "ok" | "error", message?: string): Response {
  const url = new URL(APP_CALLBACK_SCHEME);
  url.searchParams.set("status", status);
  if (message) url.searchParams.set("message", message);
  return new Response(null, { status: 302, headers: { location: url.toString() } });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const stateParam = url.searchParams.get("state");
  const oauthError = url.searchParams.get("error");

  if (oauthError) return redirect("error", oauthError);
  if (!code || !stateParam) return redirect("error", "missing_code_or_state");

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // A nonce beváltása egyben törli is: visszajátszani nem lehet.
  const state = await consumeState(supabaseAdmin, stateParam, "gmail");
  if (!state) return redirect("error", "invalid_state");

  try {
    const redirectUri = `${url.origin}${url.pathname}`;
    const tokens = await exchangeGmailCode(code, redirectUri, state.codeVerifier);
    const emailAddress = await fetchGmailProfile(tokens.accessToken);

    // A titkosítás a fiók sorához van kötve (AAD), ezért előbb meg kell
    // lennie a sornak — a tokeneket második lépésben írjuk rá.
    const { data: account, error: upsertError } = await supabaseAdmin
      .from("taskmail_email_accounts")
      .upsert(
        {
          user_id: state.userId,
          provider: "gmail",
          email_address: emailAddress,
          sync_status: "ok",
          sync_error: null,
        },
        { onConflict: "user_id,provider,email_address" },
      )
      .select("id")
      .single();
    if (upsertError || !account) throw upsertError ?? new Error("account upsert failed");

    const aad = tokenAad(account.id as string, state.userId);
    await supabaseAdmin
      .from("taskmail_email_accounts")
      .update({
        access_token_encrypted: await encryptToken(tokens.accessToken, aad),
        refresh_token_encrypted: tokens.refreshToken
          ? await encryptToken(tokens.refreshToken, aad)
          : null,
        token_expires_at: tokens.expiresAt.toISOString(),
      })
      .eq("id", account.id);

    return redirect("ok");
  } catch (err) {
    console.error("[gmail-oauth-callback]", err);
    return redirect("error", "token_exchange_failed");
  }
});
