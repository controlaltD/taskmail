// Futtatás: deno test supabase/functions/_shared/mime_test.ts
//
// A kódolási hibák csendben rontják el a levelet (ékezetek, tárgy sor), ezért
// itt kifejezetten magyar szöveggel is ellenőrzünk.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildGmailRaw, buildMimeMessage, encodeHeaderValue, toBase64Url } from "./mime.ts";

function decodeBase64Url(encoded: string): string {
  const padded = encoded.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "="));
  return new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0)));
}

function decodeBase64(encoded: string): string {
  const binary = atob(encoded.replace(/[\r\n]/g, ""));
  return new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0)));
}

Deno.test("ékezet nélküli tárgyat nem kódol feleslegesen", () => {
  assertEquals(encodeHeaderValue("Weekly report"), "Weekly report");
});

Deno.test("ékezetes tárgyat RFC 2047 encoded-word-ként kódol", () => {
  const encoded = encodeHeaderValue("Árajánlat — sürgős");
  assert(encoded.startsWith("=?UTF-8?B?"), `váratlan alak: ${encoded}`);
  assert(encoded.endsWith("?="));

  const payload = encoded.slice("=?UTF-8?B?".length, -"?=".length);
  assertEquals(decodeBase64(payload), "Árajánlat — sürgős");
});

Deno.test("a magyar levéltörzs karaktervesztés nélkül megy át", () => {
  const body = "Kedves Partnerünk!\n\nÁrváztűrő tükörfúrógép — őszi árlista.\n\nÜdvözlettel";
  const message = buildMimeMessage({
    from: "en@pelda.hu",
    to: ["cimzett@pelda.hu"],
    subject: "Teszt",
    bodyText: body,
  });

  const [, encodedBody] = message.split("\r\n\r\n");
  assertEquals(decodeBase64(encodedBody), body);
});

Deno.test("fejlécek CRLF-fel zárulnak és a törzs üres sorral kezdődik", () => {
  const message = buildMimeMessage({
    from: "en@pelda.hu",
    to: ["a@pelda.hu", "b@pelda.hu"],
    cc: ["c@pelda.hu"],
    subject: "Tárgy",
    bodyText: "szia",
  });

  assertStringIncludes(message, "To: a@pelda.hu, b@pelda.hu\r\n");
  assertStringIncludes(message, "Cc: c@pelda.hu\r\n");
  assertStringIncludes(message, "\r\n\r\n");
  assert(!message.includes("\n\n"), "sima soremelés nem maradhat a fejlécekben");
});

Deno.test("fejlécbe injektált sortörés nem hoz létre új fejlécet", () => {
  const message = buildMimeMessage({
    from: "en@pelda.hu",
    to: ["a@pelda.hu\r\nBcc: titok@pelda.hu", "rendes@pelda.hu"],
    subject: "Ártatlan\r\nX-Injected: igen",
    bodyText: "szia",
  });

  // A hibás címet eldobjuk, nem egy szóközzel összeragasztott, értelmezhetetlen
  // fejlécet állítunk elő belőle.
  assert(!message.includes("Bcc: titok@pelda.hu"), "címzettbe injektált fejléc átment");
  assert(!message.includes("X-Injected"), "tárgyba injektált fejléc átment");
  assertStringIncludes(message, "To: rendes@pelda.hu\r\n");
});

Deno.test("a hosszú törzs 76 karakterenként tördelve marad", () => {
  const body = "á".repeat(500);
  const message = buildMimeMessage({
    from: "a@pelda.hu",
    to: ["c@pelda.hu"],
    subject: "T",
    bodyText: body,
  });

  const [, encodedBody] = message.split("\r\n\r\n");
  for (const line of encodedBody.split("\r\n")) {
    assert(line.length <= 76, `túl hosszú sor: ${line.length}`);
  }
  assertEquals(decodeBase64(encodedBody), body);
});

Deno.test("HTML változattal többrészes levelet épít", () => {
  const message = buildMimeMessage({
    from: "en@pelda.hu",
    to: ["a@pelda.hu"],
    subject: "Tárgy",
    bodyText: "sima szöveg",
    bodyHtml: "<p>formázott</p>",
  });

  assertStringIncludes(message, "Content-Type: multipart/alternative;");
  assertStringIncludes(message, 'Content-Type: text/plain; charset="UTF-8"');
  assertStringIncludes(message, 'Content-Type: text/html; charset="UTF-8"');

  // A záró határolójel nélkül a levelezők csonkolt levelet látnának.
  const marker = message.match(/boundary="([^"]+)"/)?.[1];
  assert(marker, "nincs boundary a fejlécben");
  assertStringIncludes(message, `--${marker}--`);
});

Deno.test("válasznál a szálat összetartó fejlécek bekerülnek", () => {
  const message = buildMimeMessage({
    from: "en@pelda.hu",
    to: ["a@pelda.hu"],
    subject: "Re: Tárgy",
    bodyText: "válasz",
    inReplyTo: "<abc123@mail.pelda.hu>",
  });

  assertStringIncludes(message, "In-Reply-To: <abc123@mail.pelda.hu>\r\n");
  assertStringIncludes(message, "References: <abc123@mail.pelda.hu>\r\n");
});

Deno.test("base64url nem tartalmaz +, / vagy kitöltő karaktert", () => {
  // Olyan bemenet, ami sima base64-ben biztosan ad '+' vagy '/' karaktert.
  const encoded = toBase64Url("øøø???>>>~~~ árvíztűrő");
  assert(!encoded.includes("+"), encoded);
  assert(!encoded.includes("/"), encoded);
  assert(!encoded.includes("="), encoded);
});

Deno.test("a Gmail nyers üzenete visszafejtve az eredeti levelet adja", () => {
  const mail = {
    from: "en@pelda.hu",
    to: ["cimzett@pelda.hu"],
    subject: "Árajánlat",
    bodyText: "Üdvözlöm!\n\nMellékelten küldöm.\n\nÜdv",
  };

  const decoded = decodeBase64Url(buildGmailRaw(mail));
  assertEquals(decoded, buildMimeMessage(mail));
  assertStringIncludes(decoded, "From: en@pelda.hu");
});
