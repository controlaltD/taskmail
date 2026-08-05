// Cron-triggerelt (pg_cron, pl. 5 percenként) email szinkron + AI pipeline:
// minden csatlakoztatott fiókra lekéri az új leveleket, Claude-dal
// kategorizálja, és ha van felismert teendő, létrehoz egy taskmail_tasks
// sort a user alapértelmezett board-jának "todo" oszlopában.
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { classifyEmail } from "../_shared/claude.ts";
import { safeCompare } from "../_shared/crypto.ts";
import { ensureFreshAccessToken } from "../_shared/token_refresh.ts";

/** Futásonként és fiókonként legfeljebb ennyi levelet dolgozunk fel. */
const MAX_MESSAGES_PER_RUN = 50;

/**
 * A hiba okát rövid, előre definiált kóddá alakítja. A `sync_error` mezőt a
 * kliens is megjeleníti, a nyers kivételszöveg pedig kiszivárogtathatna
 * belső részleteket — például a hívott URL-t a benne lévő tokennel.
 */
function classifyFailure(reason: unknown): string {
  const text = String(reason);
  if (/token/i.test(text) && /(refresh|expire|invalid|revoke)/i.test(text)) {
    return "auth_expired";      // a felhasználónak újra össze kell kötnie a fiókot
  }
  if (/quota|rate.?limit|429/i.test(text)) return "rate_limited";
  if (/TOKEN_ENCRYPTION_KEY|decrypt|OperationError/i.test(text)) return "decrypt_failed";
  if (/ANTHROPIC|claude/i.test(text)) return "ai_unavailable";
  return "sync_failed";
}
import { fetchNewGmailMessages } from "../_shared/gmail.ts";
import { fetchNewOutlookMessages } from "../_shared/outlook.ts";
import type { RefreshableAccount } from "../_shared/token_refresh.ts";

interface Account extends RefreshableAccount {
  last_synced_at: string | null;
  ai_enabled: boolean;
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

  const fetched = account.provider === "gmail"
    ? await fetchNewGmailMessages(accessToken, account.last_synced_at)
    : await fetchNewOutlookMessages(accessToken, account.last_synced_at);

  // Felső korlát futásonként: egy hirtelen levéláradat így nem tud
  // korlátlan Claude API-költséget okozni. A maradék a következő körben jön.
  const messages = fetched.slice(0, MAX_MESSAGES_PER_RUN);

  let boardId: string | null = null;

  for (const msg of messages) {
    // A levél tartalma csak akkor kerül külső szolgáltatóhoz, ha ehhez a
    // felhasználó erre a fiókra kifejezetten hozzájárult.
    let classification = null;
    if (account.ai_enabled) {
      try {
        classification = await classifyEmail({
          subject: msg.subject,
          snippet: msg.snippet,
          fromAddress: msg.fromAddress,
        });
      } catch (err) {
        console.error("[sync-emails] classify error", err);
      }
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
    .select("id, user_id, provider, access_token_encrypted, refresh_token_encrypted, token_expires_at, last_synced_at, ai_enabled");

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
      // A részletes ok csak a szervernaplóba megy: a nyers kivételszöveg
      // tartalmazhatja a hívott URL-t a benne lévő tokennel együtt, a
      // sync_error mezőt pedig a kliens is olvassa.
      console.error(`[sync-emails] account ${account.id} failed`, result.reason);
      await supabase
        .from("taskmail_email_accounts")
        .update({ sync_status: "error", sync_error: classifyFailure(result.reason) })
        .eq("id", account.id);
    }
  }

  return new Response(
    JSON.stringify({ processed: accounts.length, failed: failures.length }),
    { headers: { "content-type": "application/json" } },
  );
});
