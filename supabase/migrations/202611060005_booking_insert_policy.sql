-- Allow authenticated users to create their own bookings.
-- Manual ticket inserts are limited to the event owner or assigned active staff.
-- Normal booking status is constrained by the event's payment settings.
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
      created_by IS NOT NULL
      AND created_by = auth.uid()
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
        )
      )
    )
    OR (
      created_by IS NULL
      AND user_id = auth.uid()
      AND EXISTS (
        SELECT 1
        FROM public.events e
        WHERE e.id = event_id
          AND (
            (COALESCE(e.require_call_confirmation, FALSE)
              AND payment_status = 'pending_confirmation')
            OR (
              NOT COALESCE(e.require_call_confirmation, FALSE)
              AND COALESCE(e.price, 0) = 0
              AND payment_status = 'confirmed'
            )
            OR (
              NOT COALESCE(e.require_call_confirmation, FALSE)
              AND COALESCE(e.price, 0) > 0
              AND COALESCE(e.pay_at_door, FALSE)
              AND payment_status = 'confirmed'
            )
            OR (
              NOT COALESCE(e.require_call_confirmation, FALSE)
              AND COALESCE(e.price, 0) > 0
              AND NOT COALESCE(e.pay_at_door, FALSE)
              AND payment_status = 'pending'
            )
          )
      )
    )
  )
);
