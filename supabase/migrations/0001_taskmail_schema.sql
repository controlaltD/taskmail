-- ═══════════════════════════════════════════════════════════════════
--  TaskMail — Supabase Migration
--  Futtatás: Supabase Dashboard → SQL Editor (UGYANAZ az instance,
--  mint a serveos_admin / serveos migrációi!)
--
--  FONTOS: minden tábla `taskmail_` prefixet kap, hogy ne ütközzön a
--  ServeOS saját `tasks`/`users`/`employees`/`venues` tábláival ugyanabban
--  a public schemában. A `venues`/`venue_users` táblák a `serveos_admin`
--  migrációjából már léteznek — ezt a migrációt csak azután futtasd.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. ENUM TYPES ────────────────────────────────────────────────
-- Szándékosan ugyanazok az értékek, mint a ServeOS `task_column`/
-- `task_priority` enumjaiban, hogy a ServeOS-be küldés mezőleképezése
-- triviális maradjon. NEM ugyanaz az enum típus (más névtér), csak
-- azonos értékkészlet.
DO $$ BEGIN
  CREATE TYPE taskmail_column AS ENUM ('todo','inprogress','review','done');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE taskmail_priority AS ENUM ('urgent','high','medium','low');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE taskmail_provider AS ENUM ('gmail','outlook');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE taskmail_sync_status AS ENUM ('pending','ok','error');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE taskmail_ai_category AS ENUM ('urgent','task','newsletter','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─── 2. EMAIL ACCOUNTS ────────────────────────────────────────────
-- Csatlakoztatott postafiókok. A tokeneket a kliens SOHA nem látja —
-- csak az Edge Function-ök írják/olvassák (service_role kulccsal).
CREATE TABLE IF NOT EXISTS taskmail_email_accounts (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider                 taskmail_provider NOT NULL,
  email_address            TEXT NOT NULL,
  access_token_encrypted   TEXT,
  refresh_token_encrypted  TEXT,
  token_expires_at         TIMESTAMPTZ,
  last_synced_at           TIMESTAMPTZ,
  sync_status              taskmail_sync_status NOT NULL DEFAULT 'pending',
  sync_error               TEXT,
  created_at               TIMESTAMPTZ DEFAULT NOW(),
  updated_at               TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, provider, email_address)
);

CREATE INDEX IF NOT EXISTS idx_taskmail_email_accounts_user ON taskmail_email_accounts(user_id);

-- ─── 3. BOARDS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taskmail_boards (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL DEFAULT 'Saját feladatok',
  is_default  BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taskmail_boards_user ON taskmail_boards(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_taskmail_boards_default
  ON taskmail_boards(user_id) WHERE is_default;

-- ─── 4. EMAIL MESSAGES ────────────────────────────────────────────
-- AI-kategorizált levelek (a `sync-emails` Edge Function tölti fel).
CREATE TABLE IF NOT EXISTS taskmail_email_messages (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id            UUID NOT NULL REFERENCES taskmail_email_accounts(id) ON DELETE CASCADE,
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_message_id   TEXT NOT NULL,
  thread_id             TEXT,
  from_address           TEXT NOT NULL,
  from_name              TEXT,
  subject               TEXT,
  snippet               TEXT,
  received_at           TIMESTAMPTZ NOT NULL,
  ai_category           taskmail_ai_category,
  ai_summary            TEXT,
  ai_processed_at       TIMESTAMPTZ,
  is_read               BOOLEAN DEFAULT FALSE,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(account_id, provider_message_id)
);

CREATE INDEX IF NOT EXISTS idx_taskmail_email_messages_user
  ON taskmail_email_messages(user_id, received_at DESC);

-- ─── 5. TASKS (Kanban kártyák) ────────────────────────────────────
-- Mezőnként igazítva a ServeOS `tasks` táblájához (lásd serveos/supabase/
-- migration.sql) — így a "Küldés ServeOS-be" művelet mezőleképezés nélkül,
-- triviálisan átküldhető. `is_archived` külön flag, NEM ötödik oszlop
-- (a ServeOS DB-jében sincs 'archived' col-érték, csak kliens-oldali trükk).
CREATE TABLE IF NOT EXISTS taskmail_tasks (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  board_id            UUID NOT NULL REFERENCES taskmail_boards(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  description         TEXT DEFAULT '',
  col                 taskmail_column NOT NULL DEFAULT 'todo',
  priority            taskmail_priority NOT NULL DEFAULT 'medium',
  label               TEXT NOT NULL DEFAULT 'ops',
  assignees           TEXT[] DEFAULT '{}',
  due_date            DATE,
  checklist           JSONB DEFAULT '[]'::jsonb,
  comments            JSONB DEFAULT '[]'::jsonb,
  sort_order          INTEGER DEFAULT 0,
  is_archived         BOOLEAN DEFAULT FALSE,
  created_by_ai       BOOLEAN DEFAULT FALSE,
  source_email_id     UUID REFERENCES taskmail_email_messages(id) ON DELETE SET NULL,
  -- ServeOS szinkron nyomkövetés — NULL amíg nincs átküldve
  serveos_venue_id    UUID,
  serveos_task_id     INTEGER,
  synced_at           TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taskmail_tasks_board ON taskmail_tasks(board_id, col);
CREATE INDEX IF NOT EXISTS idx_taskmail_tasks_user  ON taskmail_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_taskmail_tasks_email  ON taskmail_tasks(source_email_id);

-- ─── 6. UPDATED_AT TRIGGEREK ──────────────────────────────────────
CREATE OR REPLACE FUNCTION taskmail_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_taskmail_email_accounts_updated ON taskmail_email_accounts;
CREATE TRIGGER tr_taskmail_email_accounts_updated
  BEFORE UPDATE ON taskmail_email_accounts FOR EACH ROW EXECUTE FUNCTION taskmail_update_updated_at();

DROP TRIGGER IF EXISTS tr_taskmail_tasks_updated ON taskmail_tasks;
CREATE TRIGGER tr_taskmail_tasks_updated
  BEFORE UPDATE ON taskmail_tasks FOR EACH ROW EXECUTE FUNCTION taskmail_update_updated_at();

-- ─── 7. ROW LEVEL SECURITY ────────────────────────────────────────
-- A TaskMail saját tábláin szigorú, user-szintű RLS: mindenki csak a
-- saját sorait látja/írja. A ServeOS saját tábláit (tasks/venues/
-- venue_users/employees) ez a migráció NEM módosítja.
ALTER TABLE taskmail_email_accounts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE taskmail_boards          ENABLE ROW LEVEL SECURITY;
ALTER TABLE taskmail_email_messages  ENABLE ROW LEVEL SECURITY;
ALTER TABLE taskmail_tasks           ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'taskmail_email_accounts','taskmail_boards','taskmail_email_messages','taskmail_tasks'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "own_rows_select" ON %I', t);
    EXECUTE format('DROP POLICY IF EXISTS "own_rows_all" ON %I', t);
    EXECUTE format(
      'CREATE POLICY "own_rows_all" ON %I FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())',
      t
    );
    -- Edge Function-ök (service_role) mindig teljes hozzáférést kapnak —
    -- a service_role RLS-t egyébként is megkerüli, ez csak dokumentáció.
  END LOOP;
END $$;

-- ─── KÉSZ ──────────────────────────────────────────────────────────
-- Ellenőrzés:
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name LIKE 'taskmail_%';
