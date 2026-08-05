// OAuth `state` kezelés: véletlen, egyszer felhasználható nonce.
//
// A nonce mögött a szerver tartja nyilván, melyik felhasználóhoz tartozik a
// folyamat — így a kimenő URL-be nem kerül semmilyen titok. A callback a
// nonce-ot beváltja: kiolvassa a felhasználót, és azonnal törli a sort, hogy
// visszajátszani ne lehessen.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isScopeTier, type Provider, type ScopeTier } from "./oauth_scopes.ts";

/** Ennyi ideig érvényes egy megkezdett OAuth folyamat. */
const STATE_TTL_MS = 10 * 60 * 1000;

export type { Provider };

export function generateNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export async function createState(
  supabase: SupabaseClient,
  userId: string,
  provider: Provider,
  codeVerifier: string,
  scopeTier: ScopeTier,
): Promise<string> {
  const nonce = generateNonce();
  const { error } = await supabase
    .from("taskmail_oauth_state")
    .insert({
      nonce,
      user_id: userId,
      provider,
      code_verifier: codeVerifier,
      scope_tier: scopeTier,
    });
  if (error) throw new Error(`Nem sikerült létrehozni az OAuth state-et: ${error.message}`);
  return nonce;
}

export interface ConsumedState {
  userId: string;
  codeVerifier: string | null;
  scopeTier: ScopeTier;
}

/**
 * Beváltja a nonce-ot: visszaadja a hozzá tartozó felhasználót és PKCE
 * verifiert, majd törli a sort. `null`, ha ismeretlen, lejárt, más
 * szolgáltatóhoz tartozik, vagy már felhasználták — mindegyik esetben a
 * folyamatot el kell utasítani.
 */
export async function consumeState(
  supabase: SupabaseClient,
  nonce: string,
  provider: Provider,
): Promise<ConsumedState | null> {
  // A DELETE ... RETURNING atomikusan zárja ki, hogy két párhuzamos
  // callback ugyanazt a nonce-ot használja fel.
  const { data, error } = await supabase
    .from("taskmail_oauth_state")
    .delete()
    .eq("nonce", nonce)
    .eq("provider", provider)
    .select("user_id, created_at, code_verifier, scope_tier")
    .maybeSingle();

  if (error || !data) return null;

  const age = Date.now() - new Date(data.created_at as string).getTime();
  if (age > STATE_TTL_MS) return null;

  // Ismeretlen érték esetén a szűkebb jogot feltételezzük: a fiók sorára
  // beírt szint dönti el később, hogy engedünk-e küldést, ezért itt tévedni
  // csak a biztonságos irányba szabad.
  const rawTier = data.scope_tier;

  return {
    userId: data.user_id as string,
    codeVerifier: (data.code_verifier as string | null) ?? null,
    scopeTier: isScopeTier(rawTier) ? rawTier : "readonly",
  };
}
