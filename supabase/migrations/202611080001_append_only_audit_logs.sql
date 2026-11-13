-- SivoX migration 7: append-only audit streams.
-- The four operational log tables and their metadata columns already exist.
-- Keep existing ON DELETE SET NULL foreign keys so account/event deletion
-- anonymizes references without deleting the historical audit row.

CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Permit only FK-driven anonymization of a single reference column.
  IF TG_OP = 'UPDATE' AND (
    (
      OLD.user_id IS NOT NULL
      AND NEW.user_id IS NULL
      AND (to_jsonb(NEW) - 'user_id') = (to_jsonb(OLD) - 'user_id')
    )
    OR
    (
      OLD.related_event_id IS NOT NULL
      AND NEW.related_event_id IS NULL
      AND (to_jsonb(NEW) - 'related_event_id') = (to_jsonb(OLD) - 'related_event_id')
    )
  ) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Operational audit records are append-only; UPDATE and DELETE are not allowed.'
    USING ERRCODE = '55000';
END;
$$;

DO $$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'staff_logs', 'organizer_ledger', 'worker_logs', 'visitor_logs'
  ]
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS prevent_audit_log_mutation ON public.%I',
      table_name
    );
    EXECUTE format(
      'CREATE TRIGGER prevent_audit_log_mutation
       BEFORE UPDATE OR DELETE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation()',
      table_name
    );
  END LOOP;
END;
$$;

ALTER TABLE public.staff_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.worker_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitor_logs ENABLE ROW LEVEL SECURITY;

-- Replace the legacy, overly broad policies.
DROP POLICY IF EXISTS sl_delete ON public.staff_logs;
DROP POLICY IF EXISTS sl_insert ON public.staff_logs;
DROP POLICY IF EXISTS sl_select ON public.staff_logs;
DROP POLICY IF EXISTS "Staff Logs Access" ON public.staff_logs;
DROP POLICY IF EXISTS "Organizers can see logs for their events" ON public.staff_logs;
DROP POLICY IF EXISTS "Sivox audit read own or authorized team" ON public.staff_logs;
DROP POLICY IF EXISTS "Sivox authenticated audit insert" ON public.staff_logs;

DROP POLICY IF EXISTS ol_insert ON public.organizer_ledger;
DROP POLICY IF EXISTS ol_select ON public.organizer_ledger;
DROP POLICY IF EXISTS "Sivox organizer_ledger read own or event owner" ON public.organizer_ledger;
DROP POLICY IF EXISTS "Sivox organizer_ledger insert own" ON public.organizer_ledger;

DROP POLICY IF EXISTS wl_insert ON public.worker_logs;
DROP POLICY IF EXISTS wl_select ON public.worker_logs;
DROP POLICY IF EXISTS "Sivox worker_logs read own or event owner" ON public.worker_logs;
DROP POLICY IF EXISTS "Sivox worker_logs insert own" ON public.worker_logs;

DROP POLICY IF EXISTS vl_insert ON public.visitor_logs;
DROP POLICY IF EXISTS vl_select ON public.visitor_logs;
DROP POLICY IF EXISTS "Sivox visitor_logs read own or event owner" ON public.visitor_logs;
DROP POLICY IF EXISTS "Sivox visitor_logs insert own" ON public.visitor_logs;

CREATE POLICY staff_logs_select
ON public.staff_logs
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND (sa.event_id = related_event_id OR sa.event_id IS NULL)
      AND COALESCE(sa.permissions ->> 'can_view_logs', 'false') = 'true'
  )
);

CREATE POLICY staff_logs_insert
ON public.staff_logs
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY organizer_ledger_select
ON public.organizer_ledger
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND (sa.event_id = related_event_id OR sa.event_id IS NULL)
      AND COALESCE(sa.permissions ->> 'can_view_logs', 'false') = 'true'
  )
);

CREATE POLICY organizer_ledger_insert
ON public.organizer_ledger
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY worker_logs_select
ON public.worker_logs
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND (sa.event_id = related_event_id OR sa.event_id IS NULL)
      AND COALESCE(sa.permissions ->> 'can_view_logs', 'false') = 'true'
  )
);

CREATE POLICY worker_logs_insert
ON public.worker_logs
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY visitor_logs_select
ON public.visitor_logs
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY visitor_logs_insert
ON public.visitor_logs
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

-- Client roles may append and read authorized entries only.
REVOKE ALL ON public.staff_logs, public.organizer_ledger,
  public.worker_logs, public.visitor_logs FROM PUBLIC, anon;
REVOKE UPDATE, DELETE ON public.staff_logs, public.organizer_ledger,
  public.worker_logs, public.visitor_logs FROM authenticated;
GRANT SELECT, INSERT ON public.staff_logs, public.organizer_ledger,
  public.worker_logs, public.visitor_logs TO authenticated;

-- Preserve audit history when an account is deleted. The FK constraints
-- already use ON DELETE SET NULL and the audit trigger permits that one change.
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.notifications WHERE user_id = v_user_id;
  DELETE FROM public.follows WHERE user_id = v_user_id;
  DELETE FROM public.favorites WHERE user_id = v_user_id;
  DELETE FROM public.bookings WHERE user_id = v_user_id;
  DELETE FROM public.staff_assignments WHERE staff_id = v_user_id;
  DELETE FROM public.profiles WHERE id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  DELETE FROM auth.users WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.prevent_audit_log_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user() TO authenticated;