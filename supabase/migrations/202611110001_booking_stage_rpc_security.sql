-- Enforce booking stages at the database boundary.
-- Stored on the repair branch only. Review and apply explicitly to Supabase;
-- this migration is NOT executed against the live project by this change.

CREATE OR REPLACE FUNCTION public.has_event_staff_permission(
  p_event_id uuid,
  p_permission text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizer_profiles op ON op.id = e.organizer_id
      WHERE e.id = p_event_id AND op.owner_id = auth.uid()
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

REVOKE ALL ON FUNCTION public.has_event_staff_permission(uuid, text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_booking_stage_transitions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.payment_status IN ('pending', 'pending_confirmation')
     AND NEW.payment_status = 'confirmed'
     AND NOT public.has_event_staff_permission(OLD.event_id, 'can_confirm_booking') THEN
    RAISE EXCEPTION 'BOOKING_APPROVAL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NEW.payment_status = 'cancelled'
     AND OLD.payment_status IS DISTINCT FROM 'cancelled'
     AND OLD.user_id IS DISTINCT FROM auth.uid()
     AND NOT public.has_event_staff_permission(OLD.event_id, 'can_cancel') THEN
    RAISE EXCEPTION 'BOOKING_CANCELLATION_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NEW.payment_status = 'ejected'
     AND OLD.payment_status IS DISTINCT FROM 'ejected'
     AND NOT public.has_event_staff_permission(OLD.event_id, 'can_eject_guest') THEN
    RAISE EXCEPTION 'BOOKING_EJECTION_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NEW.security_cleared IS DISTINCT FROM OLD.security_cleared
     AND NEW.security_cleared = TRUE THEN
    IF OLD.payment_status <> 'confirmed'
       OR OLD.security_cleared = TRUE
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_scan') THEN
      RAISE EXCEPTION 'BOOKING_SECURITY_STAGE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF (
       NEW.payment_status IN ('used', 'late_accepted')
       AND NEW.payment_status IS DISTINCT FROM OLD.payment_status
     )
     OR (
       NEW.payment_confirmed IS DISTINCT FROM OLD.payment_confirmed
       AND NEW.payment_confirmed = TRUE
     ) THEN
    IF OLD.payment_status <> 'confirmed'
       OR OLD.security_cleared IS DISTINCT FROM TRUE
       OR OLD.payment_confirmed IS DISTINCT FROM FALSE
       OR NEW.payment_status NOT IN ('used', 'late_accepted')
       OR NEW.payment_confirmed IS DISTINCT FROM TRUE
       OR NEW.confirmed_by_manager IS DISTINCT FROM auth.uid()
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_confirm_payment')
       OR (
         NEW.payment_status = 'late_accepted'
         AND NOT public.has_event_staff_permission(OLD.event_id, 'can_mark_late')
       ) THEN
      RAISE EXCEPTION 'BOOKING_PAYMENT_STAGE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_booking_stage_transitions ON public.bookings;
CREATE TRIGGER enforce_booking_stage_transitions
BEFORE UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.enforce_booking_stage_transitions();

CREATE OR REPLACE FUNCTION public.approve_event_booking(p_booking_id uuid)
RETURNS TABLE (user_id uuid, event_id uuid, event_title text, organizer_id uuid, user_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_event_id uuid;
  v_user_name text;
BEGIN
  UPDATE public.bookings b
  SET payment_status = 'confirmed'
  WHERE b.id = p_booking_id
    AND b.payment_status IN ('pending', 'pending_confirmation')
    AND public.has_event_staff_permission(b.event_id, 'can_confirm_booking')
  RETURNING b.user_id, b.event_id, b.user_name
  INTO v_user_id, v_event_id, v_user_name;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT v_user_id, v_event_id, e.title, e.organizer_id, v_user_name
  FROM public.events e
  WHERE e.id = v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_booking_security_clearance(p_booking_id uuid)
RETURNS TABLE (user_id uuid, event_id uuid, event_title text, organizer_id uuid, user_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_event_id uuid;
  v_user_name text;
BEGIN
  UPDATE public.bookings b
  SET security_cleared = TRUE, scanned_at_security = NOW()
  WHERE b.id = p_booking_id
    AND b.payment_status = 'confirmed'
    AND b.security_cleared = FALSE
    AND public.has_event_staff_permission(b.event_id, 'can_scan')
  RETURNING b.user_id, b.event_id, b.user_name
  INTO v_user_id, v_event_id, v_user_name;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT v_user_id, v_event_id, e.title, e.organizer_id, v_user_name
  FROM public.events e
  WHERE e.id = v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_booking_manager_payment(p_booking_id uuid)
RETURNS TABLE (user_id uuid, event_id uuid, event_title text, organizer_id uuid, user_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_event_id uuid;
  v_user_name text;
BEGIN
  UPDATE public.bookings b
  SET payment_confirmed = TRUE,
      payment_status = 'used',
      scanned_at_payment = NOW(),
      scanned_at = NOW(),
      confirmed_by_manager = auth.uid()
  WHERE b.id = p_booking_id
    AND b.payment_status = 'confirmed'
    AND b.security_cleared = TRUE
    AND b.payment_confirmed = FALSE
    AND public.has_event_staff_permission(b.event_id, 'can_confirm_payment')
  RETURNING b.user_id, b.event_id, b.user_name
  INTO v_user_id, v_event_id, v_user_name;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT v_user_id, v_event_id, e.title, e.organizer_id, v_user_name
  FROM public.events e
  WHERE e.id = v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_booking_late_entry(p_booking_id uuid)
RETURNS TABLE (user_id uuid, event_id uuid, event_title text, organizer_id uuid, user_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_event_id uuid;
  v_user_name text;
BEGIN
  UPDATE public.bookings b
  SET payment_confirmed = TRUE,
      payment_status = 'late_accepted',
      scanned_at_payment = NOW(),
      scanned_at = NOW(),
      confirmed_by_manager = auth.uid()
  WHERE b.id = p_booking_id
    AND b.payment_status = 'confirmed'
    AND b.security_cleared = TRUE
    AND b.payment_confirmed = FALSE
    AND public.has_event_staff_permission(b.event_id, 'can_confirm_payment')
    AND public.has_event_staff_permission(b.event_id, 'can_mark_late')
  RETURNING b.user_id, b.event_id, b.user_name
  INTO v_user_id, v_event_id, v_user_name;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT v_user_id, v_event_id, e.title, e.organizer_id, v_user_name
  FROM public.events e
  WHERE e.id = v_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_event_booking(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_booking_security_clearance(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_booking_manager_payment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_booking_late_entry(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_event_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_booking_security_clearance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_booking_manager_payment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_booking_late_entry(uuid) TO authenticated;

-- Replace the earlier insert policy so even free and pay-at-door reservations
-- stay pending until the separate organizer/staff approval RPC succeeds.
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
        (
          COALESCE(
            (SELECT e.require_call_confirmation FROM public.events e WHERE e.id = event_id),
            FALSE
          )
          AND payment_status = 'pending_confirmation'
        )
        OR
        (
          NOT COALESCE(
            (SELECT e.require_call_confirmation FROM public.events e WHERE e.id = event_id),
            FALSE
          )
          AND payment_status = 'pending'
        )
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
