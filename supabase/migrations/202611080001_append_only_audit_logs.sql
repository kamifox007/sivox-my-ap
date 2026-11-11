-- Preserve operational audit history. This migration is additive and must be
-- reviewed before being applied to any Supabase environment.
-- Ensure the role-specific streams expected by AuditService exist on a fresh install.
-- No user foreign keys are used here so account deletion cannot cascade into audit history.
CREATE TABLE IF NOT EXISTS public.organizer_ledger (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  user_name TEXT,
  role TEXT,
  action_type TEXT,
  description TEXT,
  related_event_id UUID REFERENCES public.events(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.worker_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  user_name TEXT,
  role TEXT,
  action_type TEXT,
  description TEXT,
  related_event_id UUID REFERENCES public.events(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.visitor_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  user_name TEXT,
  role TEXT,
  action_type TEXT,
  description TEXT,
  related_event_id UUID REFERENCES public.events(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Account deletion may null the actor foreign key. Permit only that
  -- single-column anonymizing FK action; every other update/delete is blocked.
  IF TG_OP = 'UPDATE' AND (
       (
         (to_jsonb(OLD) ->> 'user_id') IS NOT NULL
         AND (to_jsonb(NEW) ->> 'user_id') IS NULL
         AND (to_jsonb(NEW) - 'user_id') = (to_jsonb(OLD) - 'user_id')
       )
       OR
       (
         (to_jsonb(OLD) ->> 'related_event_id') IS NOT NULL
         AND (to_jsonb(NEW) ->> 'related_event_id') IS NULL
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

-- Apply least-privilege access to the central and role-specific audit streams.
ALTER TABLE public.staff_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.worker_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitor_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff Logs Access" ON public.staff_logs;
DROP POLICY IF EXISTS "Organizers can see logs for their events" ON public.staff_logs;
DROP POLICY IF EXISTS "Sivox audit read own or authorized team" ON public.staff_logs;
CREATE POLICY "Sivox audit read own or authorized team"
ON public.staff_logs
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND (sa.event_id = related_event_id OR sa.event_id IS NULL)
      AND COALESCE(sa.permissions ->> 'can_view_logs', 'false') = 'true'
  )
);

DROP POLICY IF EXISTS "Sivox authenticated audit insert" ON public.staff_logs;
CREATE POLICY "Sivox authenticated audit insert"
ON public.staff_logs
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Sivox organizer_ledger read own or event owner" ON public.organizer_ledger;
CREATE POLICY "Sivox organizer_ledger read own or event owner"
ON public.organizer_ledger
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Sivox organizer_ledger insert own" ON public.organizer_ledger;
CREATE POLICY "Sivox organizer_ledger insert own"
ON public.organizer_ledger
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Sivox worker_logs read own or event owner" ON public.worker_logs;
CREATE POLICY "Sivox worker_logs read own or event owner"
ON public.worker_logs
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Sivox worker_logs insert own" ON public.worker_logs;
CREATE POLICY "Sivox worker_logs insert own"
ON public.worker_logs
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Sivox visitor_logs read own or event owner" ON public.visitor_logs;
CREATE POLICY "Sivox visitor_logs read own or event owner"
ON public.visitor_logs
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = related_event_id AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Sivox visitor_logs insert own" ON public.visitor_logs;
CREATE POLICY "Sivox visitor_logs insert own"
ON public.visitor_logs
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Keep audit rows when an account is deleted. Null the actor FK rather than
-- cascading a DELETE into an append-only operational log.
DO $$
DECLARE
  table_name text;
  fk record;
  replacement_definition text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'staff_logs',
    'organizer_ledger',
    'worker_logs',
    'visitor_logs'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
      FOR fk IN
        SELECT conname, pg_get_constraintdef(oid) AS definition
        FROM pg_constraint
        WHERE conrelid = to_regclass(format('public.%I', table_name))
          AND contype = 'f'
          AND pg_get_constraintdef(oid) ILIKE 'FOREIGN KEY (user_id)%'
      LOOP
        replacement_definition := regexp_replace(
          fk.definition,
          'ON DELETE CASCADE',
          'ON DELETE SET NULL',
          'i'
        );
        IF replacement_definition IS DISTINCT FROM fk.definition THEN
          EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN user_id DROP NOT NULL',
            table_name
          );
          EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN related_event_id DROP NOT NULL',
            table_name
          );
          EXECUTE format(
            'ALTER TABLE public.%I DROP CONSTRAINT %I',
            table_name,
            fk.conname
          );
          EXECUTE format(
            'ALTER TABLE public.%I ADD CONSTRAINT %I %s',
            table_name,
            fk.conname,
            replacement_definition
          );
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- Event deletion should detach the reference, not delete or block audit history.
DO $$
DECLARE
  table_name text;
  fk record;
  replacement_definition text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'organizer_ledger',
    'worker_logs',
    'visitor_logs'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
      FOR fk IN
        SELECT conname, pg_get_constraintdef(oid) AS definition
        FROM pg_constraint
        WHERE conrelid = to_regclass(format('public.%I', table_name))
          AND contype = 'f'
          AND pg_get_constraintdef(oid) ILIKE 'FOREIGN KEY (related_event_id)%'
      LOOP
        replacement_definition := regexp_replace(
          fk.definition,
          'ON DELETE CASCADE',
          'ON DELETE SET NULL',
          'i'
        );
        IF replacement_definition IS DISTINCT FROM fk.definition THEN
          EXECUTE format(
            'ALTER TABLE public.%I DROP CONSTRAINT %I',
            table_name,
            fk.conname
          );
          EXECUTE format(
            'ALTER TABLE public.%I ADD CONSTRAINT %I %s',
            table_name,
            fk.conname,
            replacement_definition
          );
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- PostgREST needs this relationship for visitor history's events(title, image_url) select.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.visitor_logs'::regclass
      AND contype = 'f'
      AND pg_get_constraintdef(oid) ILIKE 'FOREIGN KEY (related_event_id)%'
  ) THEN
    ALTER TABLE public.visitor_logs
      ADD CONSTRAINT visitor_logs_related_event_id_fkey
      FOREIGN KEY (related_event_id)
      REFERENCES public.events(id)
      ON DELETE SET NULL;
  END IF;
END;
$$;
