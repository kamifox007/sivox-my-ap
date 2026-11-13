-- SivoX migration 5: replace the live permissive booking insert policy.
DROP POLICY IF EXISTS bookings_insert ON public.bookings;
DROP POLICY IF EXISTS "Users can create own bookings" ON public.bookings;

CREATE POLICY bookings_insert
ON public.bookings
FOR INSERT TO authenticated
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND (
    (
      created_by IS NULL
      AND (
        (
          COALESCE(
            (SELECT e.require_call_confirmation
             FROM public.events e WHERE e.id = event_id),
            FALSE
          )
          AND payment_status = 'pending_confirmation'
        )
        OR
        (
          NOT COALESCE(
            (SELECT e.require_call_confirmation
             FROM public.events e WHERE e.id = event_id),
            FALSE
          )
          AND payment_status = 'pending'
        )
      )
    )
    OR
    (
      created_by = (SELECT auth.uid())
      AND payment_status = 'pending'
      AND COALESCE(security_cleared, FALSE) = FALSE
      AND (
        EXISTS (
          SELECT 1
          FROM public.events e
          JOIN public.organizer_profiles op ON op.id = e.organizer_id
          WHERE e.id = event_id
            AND op.user_id = (SELECT auth.uid())
        )
        OR EXISTS (
          SELECT 1
          FROM public.events e
          JOIN public.staff_assignments sa
            ON sa.organizer_id = e.organizer_id
          WHERE e.id = event_id
            AND sa.staff_id = (SELECT auth.uid())
            AND sa.status = 'active'
            AND (sa.event_id = e.id OR sa.event_id IS NULL)
            AND COALESCE(sa.permissions ->> 'can_generate', 'false') = 'true'
        )
      )
    )
  )
);