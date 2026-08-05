-- ═══════════════════════════════════════════════════════════════
-- TaskMail Migration: elküldött levelek nyilvántartása
--
-- MIÉRT KÜLÖN TÁBLA (és nem a `taskmail_email_messages` egy jelzővel):
--   1. A beérkezett levelek táblája a szinkron folyamathoz van szabva:
--      `UNIQUE(account_id, provider_message_id)` kulcs, `snippet`,
--      `ai_category`, `ai_summary` — ezek egy saját magunk írta levélre nem
--      értelmezhetők, csupa üresen hagyott mező lenne belőlük.
--   2. Ha később bekerül a szolgáltatói mappák szinkronizálása, a Gmail/
--      Outlook a SAJÁT másolatát is beszinkronizálná az általunk küldött
--      levélről — ugyanazzal a `provider_message_id`-vel, amit ide már
--      beírtunk. Külön táblával ez a ütközés fel sem merül.
--
-- RLS: eltér a szokásos `own_rows_all` mintától, szándékosan. A kliens csak
-- OLVASHATJA a saját sorait; írni kizárólag a `send-email` Edge Function tud
-- (service_role, ami az RLS-t megkerüli). Így nem lehet "elküldött" sort
-- hamisítani anélkül, hogy a levél tényleg elment volna.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS taskmail_sent_messages (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  account_id             UUID NOT NULL REFERENCES taskmail_email_accounts(id) ON DELETE CASCADE,

  -- A Gmail visszaadja az elküldött levél azonosítóját; a Microsoft Graph
  -- `sendMail` végpontja viszont üres 202-t ad, ott ez NULL marad. Ezt
  -- tudatosan elfogadjuk: a saját nyilvántartásunk az elsődleges forrás.
  provider_message_id    TEXT,
  thread_id              TEXT,

  in_reply_to_message_id UUID REFERENCES taskmail_email_messages(id) ON DELETE SET NULL,
  to_addresses           TEXT[] NOT NULL,
  cc_addresses           TEXT[] NOT NULL DEFAULT '{}',
  bcc_addresses          TEXT[] NOT NULL DEFAULT '{}',
  subject                TEXT,
  body_text              TEXT,
  body_html              TEXT,
  sent_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taskmail_sent_messages_user
  ON taskmail_sent_messages(user_id, sent_at DESC);

ALTER TABLE taskmail_sent_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own_rows_select" ON taskmail_sent_messages;
CREATE POLICY "own_rows_select" ON taskmail_sent_messages
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());
-- INSERT/UPDATE/DELETE szándékosan senkinek: csak a service_role ír ide.

-- ─── ELLENŐRZÉS ──────────────────────────────────────────────────
--   SELECT policyname, cmd, roles FROM pg_policies
--    WHERE tablename = 'taskmail_sent_messages';
--   -- pontosan egy sor: own_rows_select / SELECT / {authenticated}
