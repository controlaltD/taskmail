-- ═══════════════════════════════════════════════════════════════
-- TaskMail Migration: teljes levéltartalom tárolása
--
-- MIÉRT: eddig csak a szolgáltató által adott rövid részlet (`snippet`)
-- került be, mert a v1 csak triázsolt: kategorizált és teendőt csinált a
-- levélből. A levél elolvasásához viszont a teljes törzs kell.
--
-- A törzset NEM a szinkron tölti le (az 5 percenként fut, akár 50 levéllel
-- — a többségüket senki nem nyitja meg), hanem a `fetch-email-body` Edge
-- Function, amikor a felhasználó ténylegesen megnyit egy levelet. A
-- `body_fetched_at` jelzi, hogy megtörtént-e már: beérkezett levél tartalma
-- nem változik, ezért másodszor nincs miért lekérdezni.
--
-- Fontos: ehhez NEM kell bővebb OAuth jogosultság — a meglévő olvasási
-- jog (`gmail.readonly`, `Mail.Read`) a teljes törzsre is kiterjed.
--
-- RLS: nem változik. A meglévő `own_rows_all` szabály (`user_id =
-- auth.uid()`) az új oszlopokra is ugyanúgy érvényes.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE taskmail_email_messages
  ADD COLUMN IF NOT EXISTS body_text       TEXT,
  ADD COLUMN IF NOT EXISTS body_html       TEXT,
  ADD COLUMN IF NOT EXISTS body_fetched_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS to_addresses    TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS cc_addresses    TEXT[] NOT NULL DEFAULT '{}';

-- ─── MEGJEGYZÉS A MEGŐRZÉSI IDŐHÖZ ───────────────────────────────
-- A 0003-ban beállított 90 napos takarítás (`taskmail-email-retention`)
-- mostantól a letöltött törzseket is törli azokkal a levelekkel együtt,
-- amikből nem született teendő. Ez szándékos: a tárolt tartalom mennyisége
-- így nem nő korlátlanul, és összhangban marad az adattakarékossági
-- vállalással.

-- ─── ELLENŐRZÉS ──────────────────────────────────────────────────
--   SELECT count(*) FILTER (WHERE body_fetched_at IS NOT NULL) AS letoltott,
--          count(*) AS osszes
--     FROM taskmail_email_messages;
--   -- közvetlenül a migráció után: letoltott = 0
