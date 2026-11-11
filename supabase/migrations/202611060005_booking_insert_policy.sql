-- Guests can create reservations only in a pending state.
-- Approval is a separate, permission-checked server-side action.
-- Manual tickets are also pending and must pass the same approval/security/payment flow.
-- Stored in GitHub only; not applied to the live Supabase database.

DROP POLICY IF EXISTS "Users can create own bookings" ON public.bookings;

CREATE POLICY "Users can create own bookings"
ON public.bookings
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (
    (
      created_by IS NULL
      AND (
        (COALESCE((SELECT e.require_call_confirmation FROM public.events e WHERE e.id = event_id), FALSE)
          AND payment_status = 'pending_confirmation')
        OR
        (NOT COALESCE((SELECT e.require_call_confirmation FROM public.events e WHERE e.id = event_id), FALSE)
          AND payment_status = 'pending')
      )
    )
    OR
    (
      created_by = auth.uid()
      AND payment_status = 'pending'
      AND COALESCE(security_cleared, FALSE) = FALSE
      AND (
        EXISTS (
          SELECT 1
          FROM public.events e
          JOIN public.organizer_profiles op ON op.id = e.organizer_id
          WHERE e.id = event_id AND op.owner_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM public.staff_assignments sa
          WHERE sa.event_id = event_id
            AND sa.staff_id = auth.uid()
            AND sa.status = 'active'
            AND COALESCE(sa.permissions ->> 'can_generate', 'false') = 'true'
        )
      )
    )
  )
);
