// Cron-triggerelt (pg_cron, pl. 5 percenként) email szinkron + AI pipeline:
// minden csatlakoztatott fiókra lekéri az új leveleket, Claude-dal
// kategorizálja, és ha van felismert teendő, létrehoz egy taskmail_tasks
// sort a user alapértelmezett board-jának "todo" oszlopában.
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { classifyEmail } from "../_shared/claude.ts";
import { decryptToken, encryptToken, safeCompare } from "../_shared/crypto.ts";
import { fetchNewGmailMessages, refreshGmailToken } from "../_shared/gmail.ts";
import { fetchNewOutlookMessages, refreshOutlookToken } from "../_shared/outlook.ts";

interface Account {
  id: string;
  user_id: string;
  provider: "gmail" | "outlook";
  access_token_encrypted: string | null;
  refresh_token_encrypted: string | null;
  token_expires_at: string | null;
  last_synced_at: string | null;
}

async function ensureFreshAccessToken(supabase: SupabaseClient, account: Account): Promise<string | null> {
  if (!account.access_token_encrypted) return null;
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at) : null;
  const stillValid = expiresAt && expiresAt.getTime() - Date.now() > 60_000;
  if (stillValid) return decryptToken(account.access_token_encrypted);

  if (!account.refresh_token_encrypted) return decryptToken(account.access_token_encrypted);
  const refreshToken = await decryptToken(account.refresh_token_encrypted);

  const refreshed = account.provider === "gmail"
    ? await refreshGmailToken(refreshToken)
    : await refreshOutlookToken(refreshToken);

  await supabase
    .from("taskmail_email_accounts")
    .update({
      access_token_encrypted: await encryptToken(refreshed.accessToken),
      token_expires_at: refreshed.expiresAt.toISOString(),
    })
    .eq("id", account.id);

  return refreshed.accessToken;
}

async function getOrCreateDefaultBoardId(supabase: SupabaseClient, userId: string): Promise<string> {
  const { data: existing } = await supabase
    .from("taskmail_boards")
    .select("id")
    .eq("user_id", userId)
    .eq("is_default", true)
    .maybeSingle();
  if (existing) return existing.id as string;

  const { data: inserted, error } = await supabase
    .from("taskmail_boards")
    .insert({ user_id: userId, name: "Saját feladatok", is_default: true })
    .select("id")
    .single();
  if (error) throw error;
  return inserted.id as string;
}

async function processAccount(supabase: SupabaseClient, account: Account) {
  const accessToken = await ensureFreshAccessToken(supabase, account);
  if (!accessToken) return;

  const messages = account.provider === "gmail"
    ? await fetchNewGmailMessages(accessToken, account.last_synced_at)
    : await fetchNewOutlookMessages(accessToken, account.last_synced_at);

  let boardId: string | null = null;

  for (const msg of messages) {
    let classification;
    try {
      classification = await classifyEmail({
        subject: msg.subject,
        snippet: msg.snippet,
        fromAddress: msg.fromAddress,
      });
    } catch (err) {
      console.error("[sync-emails] classify error", err);
      classification = null;
    }

    const { data: savedMessage, error: upsertError } = await supabase
      .from("taskmail_email_messages")
      .upsert(
        {
          account_id: account.id,
          user_id: account.user_id,
          provider_message_id: msg.id,
          thread_id: msg.threadId,
          from_address: msg.fromAddress,
          from_name: msg.fromName,
          subject: msg.subject,
          snippet: msg.snippet,
          received_at: msg.receivedAt.toISOString(),
          ai_category: classification?.category ?? null,
          ai_summary: classification?.summary ?? null,
          ai_processed_at: classification ? new Date().toISOString() : null,
        },
        { onConflict: "account_id,provider_message_id" },
      )
      .select("id")
      .single();

    if (upsertError) {
      console.error("[sync-emails] message upsert error", upsertError);
      continue;
    }

    if (classification?.actionable && classification.taskTitle) {
      boardId ??= await getOrCreateDefaultBoardId(supabase, account.user_id);
      await supabase.from("taskmail_tasks").insert({
        user_id: account.user_id,
        board_id: boardId,
        title: classification.taskTitle,
        description: classification.taskDescription ?? "",
        col: "todo",
        priority: classification.taskPriority ?? "medium",
        due_date: classification.taskDueDate ?? null,
        created_by_ai: true,
        source_email_id: savedMessage.id,
      });
    }
  }

  await supabase
    .from("taskmail_email_accounts")
    .update({ last_synced_at: new Date().toISOString(), sync_status: "ok", sync_error: null })
    .eq("id", account.id);
}

Deno.serve(async (req) => {
  // A hitelesítés hiányzó konfiguráció esetén sem maradhat el: korábban
  // `if (cronSecret && ...)` állt itt, vagyis ha a titok kimaradt a
  // telepítéskor, a feltétel csendben hamis lett, és a végpont bárki
  // számára nyitva állt — a függvény ráadásul --no-verify-jwt kapcsolóval
  // fut, tehát semmi más nem védte.
  const cronSecret = Deno.env.get("SYNC_CRON_SECRET");
  if (!cronSecret) {
    console.error("[sync-emails] SYNC_CRON_SECRET nincs beállítva — a végpont letiltva");
    return new Response("Server misconfigured", { status: 500 });
  }

  const authHeader = req.headers.get("authorization") ?? "";
  if (!(await safeCompare(authHeader, `Bearer ${cronSecret}`))) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: accounts, error } = await supabase
    .from("taskmail_email_accounts")
    .select("id, user_id, provider, access_token_encrypted, refresh_token_encrypted, token_expires_at, last_synced_at");

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const results = await Promise.allSettled(
    (accounts as Account[]).map((account) => processAccount(supabase, account)),
  );

  const failures = results.filter((r) => r.status === "rejected");
  for (const [i, result] of results.entries()) {
    if (result.status === "rejected") {
      const account = (accounts as Account[])[i];
      console.error(`[sync-emails] account ${account.id} failed`, result.reason);
      await supabase
        .from("taskmail_email_accounts")
        .update({ sync_status: "error", sync_error: String(result.reason) })
        .eq("id", account.id);
    }
  }

  return new Response(
    JSON.stringify({ processed: accounts.length, failed: failures.length }),
    { headers: { "content-type": "application/json" } },
  );
});
