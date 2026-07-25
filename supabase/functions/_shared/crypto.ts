// AES-GCM token titkosítás a Web Crypto API-val (Deno-ban natívan elérhető).
// A kulcs a `TOKEN_ENCRYPTION_KEY` secretből jön, base64-kódolt 32 byte-os
// (256 bites) kulcsként. Generálás: `openssl rand -base64 32`.
//
// A titkosított érték a hozzá tartozó SORHOZ van kötve (AAD). E nélkül egy
// olyan támadó, aki írni tud az adatbázisba, átmásolhatná az egyik fiók
// tokenjét egy másik fiók sorába, és a szinkron azt gond nélkül
// visszafejtené és használná — vagyis idegen postafiókot kötne össze.
//
// Formátum:
//   "v2:" + base64(iv || ciphertext)   → AAD-hoz kötve
//   base64(iv || ciphertext)           → régi, kötés nélküli érték
// A régi formátumot még olvassuk, hogy a már tárolt tokenek működjenek;
// írni már csak v2-t írunk, tehát a következő token-frissítéskor magától
// átáll minden sor.

const V2_PREFIX = "v2:";

async function importKey(): Promise<CryptoKey> {
  const raw = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  if (!raw) throw new Error("TOKEN_ENCRYPTION_KEY nincs beállítva");
  const keyBytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** A sorhoz kötő kiegészítő hitelesített adat. */
export function tokenAad(accountId: string, userId: string): string {
  return `${accountId}:${userId}`;
}

export async function encryptToken(plain: string, aad: string): Promise<string> {
  const key = await importKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(aad) },
    key,
    new TextEncoder().encode(plain),
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return V2_PREFIX + btoa(String.fromCharCode(...combined));
}

export async function decryptToken(encoded: string, aad: string): Promise<string> {
  const key = await importKey();
  const isV2 = encoded.startsWith(V2_PREFIX);
  const payload = isV2 ? encoded.slice(V2_PREFIX.length) : encoded;

  const combined = Uint8Array.from(atob(payload), (c) => c.charCodeAt(0));
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);

  // A régi értékek AAD nélkül készültek; ha AAD-t adnánk hozzájuk, a
  // hitelesítés elbukna és jó tokent dobnánk el.
  const params: AesGcmParams = isV2
    ? { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(aad) }
    : { name: "AES-GCM", iv };

  const plainBuf = await crypto.subtle.decrypt(params, key, ciphertext);
  return new TextDecoder().decode(plainBuf);
}

/**
 * Két titok összehasonlítása úgy, hogy a futásidő ne áruljon el semmit
 * arról, hány karakter egyezett. A sima `===` az első eltérésnél kilép,
 * ezért a mérhető idejéből a titok karakterenként kitalálható.
 *
 * A hosszkülönbség is szivárogtat, ezért nem a nyers értékeket vetjük
 * össze, hanem az azonos hosszú SHA-256 lenyomataikat.
 */
export async function safeCompare(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const va = new Uint8Array(ha);
  const vb = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

// ─── PKCE ────────────────────────────────────────────────────────────
// A code_verifier a szerveren marad, a kliens felé csak a challenge megy.

export function generateCodeVerifier(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return base64Url(bytes);
}

export async function codeChallengeS256(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
