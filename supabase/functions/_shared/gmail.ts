// Gmail API integráció: OAuth code→token csere és új levelek lekérése.

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";

export interface OAuthTokens {
  accessToken: string;
  refreshToken?: string;
  expiresAt: Date;
}

export async function exchangeGmailCode(
  code: string,
  redirectUri: string,
  codeVerifier: string | null,
): Promise<OAuthTokens> {
  const params: Record<string, string> = {
    code,
    client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "",
    redirect_uri: redirectUri,
    grant_type: "authorization_code",
  };
  if (codeVerifier) params.code_verifier = codeVerifier;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
  if (!res.ok) throw new Error(`Gmail token csere sikertelen: ${await res.text()}`);
  const data = await res.json();
  return {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: new Date(Date.now() + data.expires_in * 1000),
  };
}

export async function refreshGmailToken(refreshToken: string): Promise<OAuthTokens> {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
      client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "",
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) throw new Error(`Gmail token frissítés sikertelen: ${await res.text()}`);
  const data = await res.json();
  return { accessToken: data.access_token, expiresAt: new Date(Date.now() + data.expires_in * 1000) };
}

export async function fetchGmailProfile(accessToken: string): Promise<string> {
  const res = await fetch(`${GMAIL_API}/profile`, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`Gmail profil lekérés sikertelen: ${await res.text()}`);
  const data = await res.json();
  return data.emailAddress as string;
}

export interface GmailMessage {
  id: string;
  threadId: string;
  fromAddress: string;
  fromName: string | null;
  subject: string;
  snippet: string;
  receivedAt: Date;
}

export async function fetchNewGmailMessages(
  accessToken: string,
  sinceIso: string | null,
): Promise<GmailMessage[]> {
  const query = sinceIso ? `after:${Math.floor(new Date(sinceIso).getTime() / 1000)}` : "newer_than:1d";
  const listRes = await fetch(
    `${GMAIL_API}/messages?q=${encodeURIComponent(query)}&maxResults=25`,
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  if (!listRes.ok) throw new Error(`Gmail lista lekérés sikertelen: ${await listRes.text()}`);
  const listData = await listRes.json();
  const ids: string[] = (listData.messages ?? []).map((m: { id: string }) => m.id);

  const messages: GmailMessage[] = [];
  for (const id of ids) {
    const msgRes = await fetch(
      `${GMAIL_API}/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject`,
      { headers: { authorization: `Bearer ${accessToken}` } },
    );
    if (!msgRes.ok) continue;
    const msg = await msgRes.json();
    const headers: Array<{ name: string; value: string }> = msg.payload?.headers ?? [];
    const fromHeader = headers.find((h) => h.name === "From")?.value ?? "";
    const subjectHeader = headers.find((h) => h.name === "Subject")?.value ?? "(nincs tárgy)";
    const fromMatch = fromHeader.match(/^(.*?)\s*<(.+)>$/);

    messages.push({
      id: msg.id,
      threadId: msg.threadId,
      fromAddress: fromMatch ? fromMatch[2] : fromHeader,
      fromName: fromMatch ? fromMatch[1].replace(/"/g, "").trim() || null : null,
      subject: subjectHeader,
      snippet: msg.snippet ?? "",
      receivedAt: new Date(Number(msg.internalDate)),
    });
  }
  return messages;
}
