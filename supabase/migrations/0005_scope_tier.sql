-- ═══════════════════════════════════════════════════════════════
-- TaskMail Migration: OAuth jogosultsági szint (küldési jog előkészítése)
--
-- MIÉRT: a v1 kizárólag olvasási jogot kért a Gmail/Outlook fiókokhoz
-- (`gmail.readonly`, `Mail.Read`), így a TaskMail-ből levelet küldeni nem
-- lehetett. A valódi levelezőhöz szükséges küldés bővebb jogosultságot
-- igényel, amit a felhasználónak külön engedélyeznie kell a szolgáltatónál.
--
-- Ez a migráció csak a NYILVÁNTARTÁST vezeti be: melyik kapcsolat milyen
-- szintű jogot kapott. Maga a küldés a későbbi migrációkban/függvényekben
-- épül rá.
--
-- Fontos: minden MEGLÉVŐ kapcsolat `readonly` szintre kerül — ez nem
-- visszalépés, hanem a valóság rögzítése (ezek a tokenek tényleg csak
-- olvasni tudnak). A felhasználó az appban, fiókonként tudja majd
-- felajánlott módon bővíteni.
-- ═══════════════════════════════════════════════════════════════

DO $$ BEGIN
  CREATE TYPE taskmail_scope_tier AS ENUM ('readonly', 'send');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE taskmail_email_accounts
  ADD COLUMN IF NOT EXISTS granted_scope_tier taskmail_scope_tier NOT NULL DEFAULT 'readonly',
  ADD COLUMN IF NOT EXISTS scope_upgraded_at  TIMESTAMPTZ;

-- A megkezdett OAuth folyamat is hordozza, milyen szintet kértünk — a
-- callback ebből tudja, mit írjon a fiók sorára. Alapértelmezés 'send',
-- mert új kapcsolatnál egy lépésben kérjük a bővebb jogot.
ALTER TABLE taskmail_oauth_state
  ADD COLUMN IF NOT EXISTS scope_tier taskmail_scope_tier NOT NULL DEFAULT 'send';

-- ─── ELLENŐRZÉS ──────────────────────────────────────────────────
--   SELECT email_address, provider, granted_scope_tier, scope_upgraded_at
--     FROM taskmail_email_accounts;
--   -- a meglévő soroknak 'readonly'-nak kell lenniük, upgraded_at nélkül
