-- ═══════════════════════════════════════════════════════════════════
--  TaskMail — biztonsági szigorítások
--  Futtatás: Supabase Dashboard → SQL Editor, a 0002 migráció UTÁN.
--
--  A biztonsági jelentés 05, 06, 09 és 10 pontjait fedi le.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. PKCE (10) ─────────────────────────────────────────────────
-- Az OAuth engedélykéréshez tartozó code_verifier a szerveren marad; a
-- kliens felé csak a belőle képzett challenge megy ki.
ALTER TABLE taskmail_oauth_state
  ADD COLUMN IF NOT EXISTS code_verifier TEXT;

-- ─── 2. AI-feldolgozás külön hozzájáruláshoz kötve (06) ───────────
-- A postafiók összekötése eddig automatikusan azt is jelentette, hogy
-- minden levél tárgya és tartalmi részlete kimegy a Claude API-nak. Ez
-- külön döntés, ezért külön kapcsoló, alapértelmezésben KIKAPCSOLVA.
ALTER TABLE taskmail_email_accounts
  ADD COLUMN IF NOT EXISTS ai_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN taskmail_email_accounts.ai_enabled IS
  'A felhasználó kifejezetten hozzájárult, hogy a levelek tartalma AI-feldolgozásra külső szolgáltatóhoz kerüljön.';

-- ─── 3. ServeOS-be küldés szerveroldali ellenőrzéssel (05) ────────
-- Eddig a kliens mondta meg, melyik venue-ba írjon, és ezt semmi nem
-- ellenőrizte: egy módosított kliens bármelyik üzlet tábláját megcélozhatta.
-- A "TaskMail AI" forrásjelzés is a kliensről jött, tehát hamisítható volt.
CREATE OR REPLACE FUNCTION taskmail_push_to_serveos(
  p_task_id  UUID,
  p_venue_id UUID
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task    taskmail_tasks%ROWTYPE;
  v_new_id  INTEGER;
BEGIN
  -- Csak a saját kártyád küldhető át.
  SELECT * INTO v_task
    FROM taskmail_tasks
   WHERE id = p_task_id AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_your_task' USING ERRCODE = '42501';
  END IF;

  -- És csak olyan üzletbe, aminek tagja vagy.
  IF NOT EXISTS (
    SELECT 1 FROM venue_users
     WHERE user_id = auth.uid() AND venue_id = p_venue_id AND active
  ) THEN
    RAISE EXCEPTION 'not_a_member' USING ERRCODE = '42501';
  END IF;

  -- Ugyanaz a kártya ne kerüljön át kétszer.
  IF v_task.serveos_task_id IS NOT NULL THEN
    RETURN v_task.serveos_task_id;
  END IF;

  INSERT INTO tasks (
    title, description, col, priority, label,
    assignees, due_date, checklist, comments, venue_id
  ) VALUES (
    v_task.title,
    v_task.description,
    v_task.col::TEXT::task_column,
    v_task.priority::TEXT::task_priority,
    v_task.label,
    v_task.assignees,
    v_task.due_date,
    v_task.checklist,
    -- A forrásjelzést a szerver írja, nem a kliens.
    jsonb_build_array(jsonb_build_object(
      'id',   (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
      'user', 'TaskMail',
      'text', 'Létrehozva a TaskMail appból',
      'time', TO_CHAR(NOW(), 'MM.DD HH24:MI')
    )) || COALESCE(v_task.comments, '[]'::JSONB),
    p_venue_id
  )
  RETURNING id INTO v_new_id;

  UPDATE taskmail_tasks
     SET serveos_task_id  = v_new_id,
         serveos_venue_id = p_venue_id,
         synced_at        = NOW()
   WHERE id = p_task_id;

  RETURN v_new_id;
END $$;

REVOKE ALL ON FUNCTION taskmail_push_to_serveos(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION taskmail_push_to_serveos(UUID, UUID) TO authenticated;

-- ─── 4. Megőrzési idő a leveleknek (09) ──────────────────────────
-- A levéltartalom eddig határidő nélkül gyűlt. 90 nap után törlünk, kivéve
-- amiből feladat született — arra a kártya hivatkozik.
SELECT cron.schedule(
  'taskmail-email-retention',
  '0 3 * * *',
  $$
  DELETE FROM taskmail_email_messages
   WHERE received_at < NOW() - INTERVAL '90 days'
     AND id NOT IN (
       SELECT source_email_id FROM taskmail_tasks
        WHERE source_email_id IS NOT NULL
     );
  $$
);

-- ─── KÉSZ ─────────────────────────────────────────────────────────
-- Ellenőrzés:
--   SELECT proname FROM pg_proc WHERE proname = 'taskmail_push_to_serveos';
--   SELECT jobname FROM cron.job WHERE jobname LIKE 'taskmail-%';
