-- Staff assignment permissions repair.
-- Review this migration and apply it to the Supabase project used by the app.
-- It is intentionally NOT executed against the live database by this GitHub change.

ALTER TABLE public.staff_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff Assignment Owner Insert" ON public.staff_assignments;
CREATE POLICY "Staff Assignment Owner Insert"
ON public.staff_assignments
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = organizer_id
      AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Staff Assignment Owner Update" ON public.staff_assignments;
CREATE POLICY "Staff Assignment Owner Update"
ON public.staff_assignments
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = organizer_id
      AND op.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = organizer_id
      AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Staff Assignment Staff Update Own" ON public.staff_assignments;
CREATE POLICY "Staff Assignment Staff Update Own"
ON public.staff_assignments
FOR UPDATE
TO authenticated
USING (staff_id = auth.uid())
WITH CHECK (staff_id = auth.uid());

DROP POLICY IF EXISTS "Staff Assignment Owner Delete" ON public.staff_assignments;
CREATE POLICY "Staff Assignment Owner Delete"
ON public.staff_assignments
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = organizer_id
      AND op.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Staff Assignment Staff Resign" ON public.staff_assignments;
CREATE POLICY "Staff Assignment Staff Resign"
ON public.staff_assignments
FOR DELETE
TO authenticated
USING (staff_id = auth.uid());
