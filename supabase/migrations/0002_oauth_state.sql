-- ═══════════════════════════════════════════════════════════════════
--  TaskMail — OAuth state (nonce) tábla
--  Futtatás: Supabase Dashboard → SQL Editor, a 0001 migráció UTÁN.
--
--  Miért kell: korábban a Flutter app a felhasználó Supabase hozzáférési
--  tokenjét tette az OAuth `state` paraméterébe. Az URL végigmegy a Google
--  és a Microsoft szerverein, bekerül a böngésző előzményeibe és a
--  function-naplókba — onnan a token kiolvasható és a munkamenet
--  eltéríthető. Helyette egy véletlen, egyszer felhasználható nonce megy
--  ki, és a hozzá tartozó felhasználót a szerver tartja nyilván.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS taskmail_oauth_state (
  nonce       TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider    taskmail_provider NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taskmail_oauth_state_created
  ON taskmail_oauth_state(created_at);

-- RLS bekapcsolva, de SZÁNDÉKOSAN egyetlen policy nélkül:
-- így sem az anon, sem a bejelentkezett kliens nem lát rá és nem ír bele.
-- Csak a service_role fér hozzá (az RLS-t megkerüli), vagyis kizárólag az
-- Edge Function-ök. A nonce sosem kerülhet kliensoldali lekérdezésbe.
ALTER TABLE taskmail_oauth_state ENABLE ROW LEVEL SECURITY;

-- Elárvult nonce-ok takarítása (a callback amúgy is törli a felhasználtat,
-- ez a félbehagyott folyamatok után marad).
SELECT cron.schedule(
  'taskmail-oauth-state-cleanup',
  '*/30 * * * *',
  $$ DELETE FROM taskmail_oauth_state WHERE created_at < NOW() - INTERVAL '1 hour'; $$
);
