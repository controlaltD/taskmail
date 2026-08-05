-- ═══════════════════════════════════════════════════════════════
-- TaskMail Migration: piszkozatok
--
-- MIÉRT: a megkezdett levél eddig elveszett, ha a felhasználó kilépett a
-- levélíróból. A piszkozat gépelés közben, automatikusan mentődik, és a
-- Piszkozatok mappából folytatható.
--
-- Ez a tábla TaskMail-oldali: a Gmail/Outlook saját piszkozat-mappájával
-- nem szinkronizál. (Ahhoz szolgáltatónkénti írási jog és mappa-tükrözés
-- kellene — külön, későbbi munka.)
--
-- NINCS hozzá Edge Function: a piszkozat nem tartalmaz titkot, és nem nyúl
-- tokenhez, ezért a kliens közvetlenül írja, RLS mögött — ugyanaz a minta,
-- amit a fiókonkénti AI-kapcsoló is használ. A tényleges küldés viszont
-- továbbra is a `send-email` függvényen megy át, ott van a jogosultság-
-- ellenőrzés.
-- ═══════════════════════════════════════════════════════════════

DO $$ BEGIN
  CREATE TYPE taskmail_draft_status AS ENUM ('draft', 'sent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS taskmail_drafts (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  account_id             UUID REFERENCES taskmail_email_accounts(id) ON DELETE CASCADE,

  -- Válasz esetén melyik levélre. A hivatkozott levél törlődhet (90 napos
  -- takarítás), ettől a piszkozat még megmarad — ilyenkor sima levélként
  -- küldhető tovább.
  in_reply_to_message_id UUID REFERENCES taskmail_email_messages(id) ON DELETE SET NULL,

  to_addresses           TEXT[] NOT NULL DEFAULT '{}',
  cc_addresses           TEXT[] NOT NULL DEFAULT '{}',
  bcc_addresses          TEXT[] NOT NULL DEFAULT '{}',
  subject                TEXT NOT NULL DEFAULT '',
  body_text              TEXT NOT NULL DEFAULT '',

  -- Az elküldött piszkozatot nem töröljük, hanem megjelöljük: így a küldés
  -- utólag is visszakövethető, a Piszkozatok lista pedig egyszerűen szűr.
  status                 taskmail_draft_status NOT NULL DEFAULT 'draft',
  sent_message_id        UUID REFERENCES taskmail_sent_messages(id) ON DELETE SET NULL,

  created_at             TIMESTAMPTZ DEFAULT NOW(),
  updated_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taskmail_drafts_user
  ON taskmail_drafts(user_id, updated_at DESC);

ALTER TABLE taskmail_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own_rows_all" ON taskmail_drafts;
CREATE POLICY "own_rows_all" ON taskmail_drafts
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  -- Eltér a többi tábla mintájától: a `user_id` mellett azt is megköveteli,
  -- hogy a hivatkozott fiók tényleg a hívóé legyen. Enélkül a saját sorába
  -- bárki beírhatná más `account_id`-ját. A küldést ez önmagában nem
  -- befolyásolná (a `send-email` külön ellenőriz), de inkonzisztens sor így
  -- létre sem jöhet.
  WITH CHECK (
    user_id = auth.uid()
    AND (
      account_id IS NULL
      OR EXISTS (
        SELECT 1 FROM taskmail_email_accounts a
         WHERE a.id = account_id AND a.user_id = auth.uid()
      )
    )
  );

DROP TRIGGER IF EXISTS tr_taskmail_drafts_updated ON taskmail_drafts;
CREATE TRIGGER tr_taskmail_drafts_updated
  BEFORE UPDATE ON taskmail_drafts
  FOR EACH ROW EXECUTE FUNCTION taskmail_update_updated_at();

-- ─── ELLENŐRZÉS ──────────────────────────────────────────────────
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'taskmail_drafts';
--   SELECT tgname FROM pg_trigger WHERE tgrelid = 'taskmail_drafts'::regclass
--     AND NOT tgisinternal;
