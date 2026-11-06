-- Allow authenticated users to create their own bookings.
-- Manual ticket inserts are limited to the event owner or assigned active staff.
-- This migration is stored in GitHub only and is not applied to live Supabase.

DROP POLICY IF EXISTS "Users can create own bookings" ON public.bookings;

CREATE POLICY "Users can create own bookings"
ON public.bookings
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (
    created_by IS NULL
    OR (
      created_by = auth.uid()
      AND (
        EXISTS (
          SELECT 1
          FROM public.events e
          JOIN public.organizer_profiles op ON op.id = e.organizer_id
          WHERE e.id = event_id
            AND op.owner_id = auth.uid()
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
  )
);
