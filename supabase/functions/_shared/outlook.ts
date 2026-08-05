// Microsoft Graph API integráció: OAuth code→token csere és új levelek lekérése.

import { OUTLOOK_SCOPES, type ScopeTier } from "./oauth_scopes.ts";

const TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
const GRAPH_API = "https://graph.microsoft.com/v1.0";

export interface OAuthTokens {
  accessToken: string;
  refreshToken?: string;
  expiresAt: Date;
}

export async function exchangeOutlookCode(
  code: string,
  redirectUri: string,
  codeVerifier: string | null,
  scopeTier: ScopeTier,
): Promise<OAuthTokens> {
  const params: Record<string, string> = {
    code,
    client_id: Deno.env.get("MICROSOFT_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("MICROSOFT_CLIENT_SECRET") ?? "",
    redirect_uri: redirectUri,
    grant_type: "authorization_code",
    scope: OUTLOOK_SCOPES[scopeTier],
  };
  if (codeVerifier) params.code_verifier = codeVerifier;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
  if (!res.ok) throw new Error(`Outlook token csere sikertelen: ${await res.text()}`);
  const data = await res.json();
  return {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: new Date(Date.now() + data.expires_in * 1000),
  };
}

export async function refreshOutlookToken(refreshToken: string): Promise<OAuthTokens> {
  // A `scope` szándékosan hiányzik: a Microsoft ilyenkor az eredetileg
  // engedélyezett jogosultságokkal adja vissza a tokent. Ha itt fixen
  // megadnánk, egy scope-bővítés után a frissítés visszaszűkítené a
  // hozzáférést a régi szintre.
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: Deno.env.get("MICROSOFT_CLIENT_ID") ?? "",
      client_secret: Deno.env.get("MICROSOFT_CLIENT_SECRET") ?? "",
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) throw new Error(`Outlook token frissítés sikertelen: ${await res.text()}`);
  const data = await res.json();
  return { accessToken: data.access_token, expiresAt: new Date(Date.now() + data.expires_in * 1000) };
}

export async function fetchOutlookProfile(accessToken: string): Promise<string> {
  const res = await fetch(`${GRAPH_API}/me`, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`Outlook profil lekérés sikertelen: ${await res.text()}`);
  const data = await res.json();
  return (data.mail ?? data.userPrincipalName) as string;
}

export interface OutlookMessage {
  id: string;
  threadId: string;
  fromAddress: string;
  fromName: string | null;
  subject: string;
  snippet: string;
  receivedAt: Date;
}

/**
 * Egy levél teljes tartalma. A Graph a Gmailnél egyszerűbb: nincs MIME-fa,
 * a `body.content` már kész szöveg vagy HTML, a `contentType` dönti el melyik.
 */
export async function fetchOutlookMessageBody(
  accessToken: string,
  providerMessageId: string,
): Promise<{
  bodyText: string | null;
  bodyHtml: string | null;
  toAddresses: string[];
  ccAddresses: string[];
}> {
  const res = await fetch(
    `${GRAPH_API}/me/messages/${providerMessageId}?$select=body,toRecipients,ccRecipients`,
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) throw new Error(`Outlook levél lekérés sikertelen: ${await res.text()}`);
  const msg = await res.json();

  const body = msg.body as { contentType?: string; content?: string } | undefined;
  const isHtml = (body?.contentType ?? "").toLowerCase() === "html";
  const content = body?.content ?? null;

  const addresses = (list: unknown): string[] =>
    ((list as Array<{ emailAddress?: { address?: string } }>) ?? [])
      .map((r) => r.emailAddress?.address ?? "")
      .filter((a) => a.length > 0);

  return {
    bodyText: isHtml ? null : content,
    bodyHtml: isHtml ? content : null,
    toAddresses: addresses(msg.toRecipients),
    ccAddresses: addresses(msg.ccRecipients),
  };
}

export async function fetchNewOutlookMessages(
  accessToken: string,
  sinceIso: string | null,
): Promise<OutlookMessage[]> {
  const since = sinceIso ?? new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const filter = encodeURIComponent(`receivedDateTime gt ${since}`);
  const res = await fetch(
    `${GRAPH_API}/me/mailFolders/inbox/messages?$filter=${filter}&$top=25&$orderby=receivedDateTime desc`,
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) throw new Error(`Outlook lista lekérés sikertelen: ${await res.text()}`);
  const data = await res.json();

  return ((data.value ?? []) as Array<Record<string, unknown>>).map((msg) => {
    const from = msg.from as { emailAddress?: { address?: string; name?: string } } | undefined;
    return {
      id: msg.id as string,
      threadId: (msg.conversationId as string) ?? (msg.id as string),
      fromAddress: from?.emailAddress?.address ?? "",
      fromName: from?.emailAddress?.name ?? null,
      subject: (msg.subject as string) ?? "(nincs tárgy)",
      snippet: (msg.bodyPreview as string) ?? "",
      receivedAt: new Date(msg.receivedDateTime as string),
    };
  });
}
