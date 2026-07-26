-- ═══════════════════════════════════════════════════════════════
-- TaskMail Migration: sync-emails periodikus ütemezése
--
-- MIÉRT: a `sync-emails` Edge Function eddig sehonnan nem lett hívva —
-- csak a levél-megőrzési takarítás (`taskmail-email-retention`, lásd
-- 0003) volt beütemezve. AI-feldolgozás és task-generálás nélküle
-- SOHA nem futott volna le automatikusan.
--
-- A `sync-emails` a `SYNC_CRON_SECRET` Edge Function secret ellenőrzött
-- `Authorization: Bearer <secret>` fejlécet vár (lásd
-- supabase/functions/sync-emails/index.ts). Ezt a titkot NEM írjuk be
-- nyílt szövegben a migrációba (a fájl git-be kerül) — a Supabase
-- Vault-ban tároljuk, és a cron job onnan olvassa ki minden futáskor.
--
-- FUTTATÁS ELŐTT: cseréld ki a két <<...>> jelölt helyet a saját
-- projekted adataira, ÉS előbb futtasd le a SYNC_CRON_SECRET-et a
-- Vault-ba mentő blokkot — a secretnek egyeznie kell azzal az
-- értékkel, amit `supabase secrets set SYNC_CRON_SECRET=...`-tal az
-- Edge Function oldalára is beállítasz.
-- ═══════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_net;

-- 1) A cron secret elmentése a Vault-ba (csak egyszer kell futtatni;
--    ha update kell, `select vault.update_secret(...)`-tal).
--    Cseréld ki: <<UGYANAZ AZ ÉRTÉK, AMIT A SYNC_CRON_SECRET Edge
--    Function secretnek is beállítottál>>
SELECT vault.create_secret(
  '<<SYNC_CRON_SECRET_ÉRTÉKE>>',
  'taskmail_sync_cron_secret'
);

-- 2) Az ütemezés — 5 percenként meghívja a sync-emails function-t.
--    Cseréld ki: <<A SAJÁT PROJECTED URL-JE, PL. https://xxxx.supabase.co>>
SELECT cron.schedule(
  'taskmail-sync-emails',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url     := '<<SUPABASE_PROJECT_URL>>/functions/v1/sync-emails',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret FROM vault.decrypted_secrets
         WHERE name = 'taskmail_sync_cron_secret'
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ─── ELLENŐRZÉS ─────────────────────────────────────────────────
--   SELECT jobname, schedule FROM cron.job WHERE jobname LIKE 'taskmail-%';
--   -- öt perc múlva:
--   SELECT * FROM net._http_response ORDER BY id DESC LIMIT 5;
