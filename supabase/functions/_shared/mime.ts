// RFC 2822 üzenet összeállítása a Gmail `messages.send` végpontjához.
//
// MIÉRT KÜLÖN, TESZTELT MODUL: a Gmail nyers, base64url-kódolt MIME üzenetet
// vár. Az itteni kódolási hibák nem szállnak el hangosan — csendben elrontják
// a levelet: az ékezetes betűk krix-kraxként érkeznek meg a címzetthez, vagy a
// tárgy sor törik el. Ezt csak teszttel lehet észrevenni idejében, ezért van
// hozzá `mime_test.ts`.
//
// Az Outlook (Microsoft Graph) NEM ezt használja: ott a `/me/sendMail` végpont
// strukturált JSON-t fogad, nincs szükség kézi MIME építésre.

/** RFC 2822: a fejlécsorokat CRLF zárja, nem sima soremelés. */
const CRLF = "\r\n";

export interface OutgoingMail {
  from: string;
  to: string[];
  cc?: string[];
  bcc?: string[];
  subject: string;
  bodyText: string;
  bodyHtml?: string | null;
  /** A megválaszolt levél `Message-ID` fejléce, ha válaszról van szó. */
  inReplyTo?: string | null;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function utf8Base64(text: string): string {
  return base64(new TextEncoder().encode(text));
}

/** A base64 sorait 76 karakternél tördeljük, ahogy a MIME előírja. */
function wrapBase64(encoded: string): string {
  const lines: string[] = [];
  for (let i = 0; i < encoded.length; i += 76) {
    lines.push(encoded.slice(i, i + 76));
  }
  return lines.join(CRLF);
}

function isAscii(text: string): boolean {
  // deno-lint-ignore no-control-regex
  return /^[\x00-\x7F]*$/.test(text);
}

/**
 * RFC 2047 "encoded-word": a fejlécek csak ASCII-t vihetnek, ezért az ékezetes
 * tárgyat kódolni kell. Ékezet nélküli szöveget érintetlenül hagyunk, hogy a
 * levél forrása olvasható maradjon.
 */
export function encodeHeaderValue(value: string): string {
  if (isAscii(value)) return value;
  return `=?UTF-8?B?${utf8Base64(value)}?=`;
}

function boundary(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return `----=_TaskMail_${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

/** Fejlécbe injektált sortöréssel további fejléceket lehetne becsempészni. */
function sanitizeHeader(value: string): string {
  return value.replace(/[\r\n]+/g, " ").trim();
}

/**
 * Egy email cím nem tartalmaz szóközt, és pontosan egy `@` van benne. A
 * sortörés kiszűrése önmagában kevés lenne: abból csak egy szóközzel
 * összeragasztott, hibás fejléc lenne (`To: a@b.hu Bcc: c@d.hu`), amit a
 * fogadó szerver kiszámíthatatlanul értelmez. Az ilyen bejegyzést inkább
 * eldobjuk — a hívó előtte úgyis validál, ide már csak hiba vagy támadás
 * juthat el.
 */
function isPlausibleAddress(value: string): boolean {
  return /^[^\s@]+@[^\s@]+$/.test(value);
}

export function validAddresses(addresses: string[]): string[] {
  return addresses.map(sanitizeHeader).filter(isPlausibleAddress);
}

function addressList(addresses: string[]): string {
  return validAddresses(addresses).join(", ");
}

/** Összeállítja a teljes RFC 2822 üzenetet. */
export function buildMimeMessage(mail: OutgoingMail): string {
  const headers: string[] = [
    `From: ${sanitizeHeader(mail.from)}`,
    `To: ${addressList(mail.to)}`,
  ];

  if (mail.cc?.length) headers.push(`Cc: ${addressList(mail.cc)}`);
  if (mail.bcc?.length) headers.push(`Bcc: ${addressList(mail.bcc)}`);

  headers.push(`Subject: ${encodeHeaderValue(sanitizeHeader(mail.subject))}`);

  if (mail.inReplyTo) {
    const id = sanitizeHeader(mail.inReplyTo);
    headers.push(`In-Reply-To: ${id}`);
    // A References fejléc tartja össze a szálat azoknál a kliensekben, amik
    // nem a szolgáltató saját szál-azonosítóját nézik.
    headers.push(`References: ${id}`);
  }

  headers.push("MIME-Version: 1.0");

  const html = mail.bodyHtml?.trim();

  // Csak szöveges levél: nincs szükség többrészes szerkezetre.
  if (!html) {
    headers.push('Content-Type: text/plain; charset="UTF-8"');
    headers.push("Content-Transfer-Encoding: base64");
    return `${headers.join(CRLF)}${CRLF}${CRLF}${wrapBase64(utf8Base64(mail.bodyText))}`;
  }

  // Szöveg + HTML: a levelezők a nekik megfelelő változatot választják ki.
  const marker = boundary();
  headers.push(`Content-Type: multipart/alternative; boundary="${marker}"`);

  const parts = [
    [
      `--${marker}`,
      'Content-Type: text/plain; charset="UTF-8"',
      "Content-Transfer-Encoding: base64",
      "",
      wrapBase64(utf8Base64(mail.bodyText)),
    ].join(CRLF),
    [
      `--${marker}`,
      'Content-Type: text/html; charset="UTF-8"',
      "Content-Transfer-Encoding: base64",
      "",
      wrapBase64(utf8Base64(html)),
    ].join(CRLF),
    `--${marker}--`,
  ];

  return `${headers.join(CRLF)}${CRLF}${CRLF}${parts.join(CRLF)}`;
}

/**
 * A Gmail base64url-t vár (RFC 4648 §5): `+`→`-`, `/`→`_`, kitöltés nélkül.
 * Sima base64-gyel a kérés elszáll, vagy sérült levelet küld.
 */
export function toBase64Url(raw: string): string {
  return utf8Base64(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function buildGmailRaw(mail: OutgoingMail): string {
  return toBase64Url(buildMimeMessage(mail));
}
