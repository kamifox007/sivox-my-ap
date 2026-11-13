-- SivoX migration 10: tighten event report scoping and avoid a privileged
-- public RPC for a helper that can safely run under caller permissions.

CREATE OR REPLACE FUNCTION public.has_event_staff_permission(
  p_event_id UUID,
  p_permission TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizer_profiles op ON op.id = e.organizer_id
      WHERE e.id = p_event_id
        AND op.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.staff_assignments sa ON sa.organizer_id = e.organizer_id
      WHERE e.id = p_event_id
        AND sa.staff_id = auth.uid()
        AND sa.status = 'active'
        AND (sa.event_id = p_event_id OR sa.event_id IS NULL)
        AND COALESCE(sa.permissions ->> p_permission, 'false') = 'true'
    )
  );
$$;

REVOKE ALL ON FUNCTION public.has_event_staff_permission(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_event_staff_permission(UUID, TEXT) TO authenticated;

DROP POLICY IF EXISTS event_reports_select ON public.event_reports;

CREATE POLICY event_reports_select
ON public.event_reports
FOR SELECT TO authenticated
USING (
  reporter_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = event_reports.event_id
      AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.event_id = event_reports.event_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_view_stats', 'false') = 'true'
  )
);

-- No bookings exist yet. Normalize empty guest counts and enforce valid values
-- for future reservations, matching the Flutter service's 1..10 range.
UPDATE public.bookings
SET num_guests = 1
WHERE num_guests IS NULL;

ALTER TABLE public.bookings
  ALTER COLUMN num_guests SET DEFAULT 1,
  ALTER COLUMN num_guests SET NOT NULL;

ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_num_guests_range_check;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_num_guests_range_check
  CHECK (num_guests BETWEEN 1 AND 10);