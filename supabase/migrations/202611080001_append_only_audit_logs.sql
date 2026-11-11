-- Preserve operational audit history. This migration is additive and must be
-- reviewed before being applied to any Supabase environment.
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'Operational audit records are append-only; UPDATE and DELETE are not allowed.'
    USING ERRCODE = '55000';
END;
$$;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'staff_logs',
    'organizer_ledger',
    'worker_logs',
    'visitor_logs'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
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
    END IF;
  END LOOP;
END;
$$;

-- The application writes metadata with every audit entry. Add it to the legacy
-- central log and to optional role streams when those tables exist.
ALTER TABLE public.staff_logs
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['organizer_ledger', 'worker_logs', 'visitor_logs']
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT %L::jsonb',
        table_name,
        '{}'
      );
    END IF;
  END LOOP;
END;
$$;

DROP POLICY IF EXISTS "Sivox authenticated audit insert" ON public.staff_logs;
CREATE POLICY "Sivox authenticated audit insert"
ON public.staff_logs
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());
