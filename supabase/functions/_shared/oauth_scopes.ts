// OAuth scope-ok egyetlen igazságforrása.
//
// MIÉRT KÜLÖN FÁJL: a scope string korábban három helyen élt párhuzamosan
// (oauth-start authorize URL-je, és az outlook.ts-ben a token-csere ÉS a
// token-frissítés kérésének törzsében is, hardkódolva). Emiatt a scope
// bővítése az egyik helyen csendben hatástalan maradhatott volna: a
// felhasználó a Google/Microsoft képernyőn megadja a bővebb jogot, a
// token-csere viszont a régi, szűkebb scope-ot kéri vissza, és a kapott
// hozzáférés végül nem tud küldeni.

export type Provider = "gmail" | "outlook";

/**
 * A tárolt tokenhez tartozó jogosultsági szint.
 * - `readonly`: csak levélolvasás (a v1 viselkedés)
 * - `send`: olvasás + küldés
 *
 * Megjegyzés: a teljes levéltörzs olvasásához (Gmail `format=full`,
 * Graph `$select=body`) NEM kell `send` szint — azt a `readonly` is fedi.
 */
export type ScopeTier = "readonly" | "send";

export const GMAIL_SCOPES: Record<ScopeTier, string> = {
  readonly: "https://www.googleapis.com/auth/gmail.readonly",
  send: "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send",
};

export const OUTLOOK_SCOPES: Record<ScopeTier, string> = {
  readonly: "offline_access Mail.Read",
  send: "offline_access Mail.Read Mail.Send",
};

export function scopeFor(provider: Provider, tier: ScopeTier): string {
  return provider === "gmail" ? GMAIL_SCOPES[tier] : OUTLOOK_SCOPES[tier];
}

export function isScopeTier(value: unknown): value is ScopeTier {
  return value === "readonly" || value === "send";
}
