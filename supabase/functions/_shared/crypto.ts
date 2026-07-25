// AES-GCM token titkosítás a Web Crypto API-val (Deno-ban natívan elérhető).
// A kulcs a `TOKEN_ENCRYPTION_KEY` secretből jön, base64-kódolt 32 byte-os
// (256 bites) kulcsként. Generálás: `openssl rand -base64 32`.

async function importKey(): Promise<CryptoKey> {
  const raw = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  if (!raw) throw new Error("TOKEN_ENCRYPTION_KEY nincs beállítva");
  const keyBytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptToken(plain: string): Promise<string> {
  const key = await importKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(plain),
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return btoa(String.fromCharCode(...combined));
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

export async function decryptToken(encoded: string): Promise<string> {
  const key = await importKey();
  const combined = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const plainBuf = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
  return new TextDecoder().decode(plainBuf);
}
