-- SivoX migration 1: staff assignment authorization.
-- Live schema uses organizer_profiles.user_id (not owner_id).
ALTER TABLE public.staff_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sa_select ON public.staff_assignments;
DROP POLICY IF EXISTS sa_insert ON public.staff_assignments;
DROP POLICY IF EXISTS sa_update ON public.staff_assignments;
DROP POLICY IF EXISTS sa_delete ON public.staff_assignments;
DROP POLICY IF EXISTS "Staff Assignment Owner Insert" ON public.staff_assignments;
DROP POLICY IF EXISTS "Staff Assignment Owner Update" ON public.staff_assignments;
DROP POLICY IF EXISTS "Staff Assignment Staff Update Own" ON public.staff_assignments;
DROP POLICY IF EXISTS "Staff Assignment Owner Delete" ON public.staff_assignments;
DROP POLICY IF EXISTS "Staff Assignment Staff Resign" ON public.staff_assignments;

CREATE POLICY sa_select
ON public.staff_assignments
FOR SELECT TO authenticated
USING (
  staff_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = organizer_id AND op.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY sa_insert
ON public.staff_assignments
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = organizer_id AND op.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY sa_owner_update
ON public.staff_assignments
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = organizer_id AND op.user_id = (SELECT auth.uid())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = organizer_id AND op.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY sa_staff_accept_update
ON public.staff_assignments
FOR UPDATE TO authenticated
USING (staff_id = (SELECT auth.uid()) AND status = 'pending')
WITH CHECK (
  staff_id = (SELECT auth.uid())
  AND status IN ('active', 'declined')
);

CREATE POLICY sa_owner_delete
ON public.staff_assignments
FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = organizer_id AND op.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY sa_staff_resign_delete
ON public.staff_assignments
FOR DELETE TO authenticated
USING (staff_id = (SELECT auth.uid()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_assignments TO authenticated;