// A tárolt hozzáférési token kiolvasása, és lejárat esetén frissítése.
//
// MIÉRT KÜLÖN MODUL: eredetileg a `sync-emails` privát segédfüggvénye volt,
// de a levéltörzs igény szerinti letöltéséhez (`fetch-email-body`) és később
// a küldéshez is pontosan ugyanerre van szükség. Két példányban tartani
// kockázatos: a titkosítás AAD-kötése és a lejárat-kezelés apró eltérése is
// nehezen észrevehető hibát okozna.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decryptToken, encryptToken, tokenAad } from "./crypto.ts";
import { refreshGmailToken } from "./gmail.ts";
import { refreshOutlookToken } from "./outlook.ts";

/** A token-frissítéshez szükséges mezők egy `taskmail_email_accounts` sorból. */
export interface RefreshableAccount {
  id: string;
  user_id: string;
  provider: "gmail" | "outlook";
  access_token_encrypted: string | null;
  refresh_token_encrypted: string | null;
  token_expires_at: string | null;
}

/** Ennyivel a lejárat előtt már frissítünk, hogy a hívás ne fusson bele. */
const EXPIRY_MARGIN_MS = 60_000;

export async function ensureFreshAccessToken(
  supabase: SupabaseClient,
  account: RefreshableAccount,
): Promise<string | null> {
  if (!account.access_token_encrypted) return null;
  // Az AAD a sorhoz köti a titkosított értéket: egy másik fiók sorába
  // átmásolt token visszafejtése itt hibára fut.
  const aad = tokenAad(account.id, account.user_id);

  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at) : null;
  const stillValid = expiresAt && expiresAt.getTime() - Date.now() > EXPIRY_MARGIN_MS;
  if (stillValid) return decryptToken(account.access_token_encrypted, aad);

  if (!account.refresh_token_encrypted) return decryptToken(account.access_token_encrypted, aad);
  const refreshToken = await decryptToken(account.refresh_token_encrypted, aad);

  const refreshed = account.provider === "gmail"
    ? await refreshGmailToken(refreshToken)
    : await refreshOutlookToken(refreshToken);

  await supabase
    .from("taskmail_email_accounts")
    .update({
      access_token_encrypted: await encryptToken(refreshed.accessToken, aad),
      token_expires_at: refreshed.expiresAt.toISOString(),
    })
    .eq("id", account.id);

  return refreshed.accessToken;
}
