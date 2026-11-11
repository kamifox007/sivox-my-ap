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
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    IF current_setting('app.ticket_transfer', TRUE) IS DISTINCT FROM 'on'
       OR OLD.user_id IS DISTINCT FROM auth.uid()
       OR OLD.payment_status NOT IN ('pending', 'pending_confirmation', 'confirmed')
       OR OLD.security_cleared IS TRUE
       OR OLD.payment_confirmed IS TRUE THEN
      RAISE EXCEPTION 'BOOKING_TRANSFER_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF OLD.payment_status = 'confirmed'
     AND NEW.payment_status IN ('pending', 'pending_confirmation') THEN
    RAISE EXCEPTION 'BOOKING_APPROVAL_CANNOT_BE_REVERSED' USING ERRCODE = '55000';
  END IF;

  IF OLD.payment_status IN ('used', 'late_accepted')
     AND NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
    RAISE EXCEPTION 'BOOKING_ATTENDANCE_IS_FINAL' USING ERRCODE = '55000';
  END IF;

  IF OLD.security_cleared = TRUE AND NEW.security_cleared = FALSE THEN
    RAISE EXCEPTION 'BOOKING_SECURITY_CLEARANCE_IS_FINAL' USING ERRCODE = '55000';
  END IF;

  IF OLD.payment_confirmed = TRUE AND NEW.payment_confirmed = FALSE THEN
    RAISE EXCEPTION 'BOOKING_PAYMENT_CONFIRMATION_IS_FINAL' USING ERRCODE = '55000';
  END IF;

  IF OLD.confirmed_by_manager IS NOT NULL
     AND NEW.confirmed_by_manager IS DISTINCT FROM OLD.confirmed_by_manager THEN
    RAISE EXCEPTION 'BOOKING_PAYMENT_ACTOR_IS_FINAL' USING ERRCODE = '55000';
  END IF;

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

  IF NEW.payment_status = 'cancelled'
     AND OLD.user_id = auth.uid()
     AND (
       (to_jsonb(NEW) - ARRAY['payment_status', 'cancellation_reason'])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['payment_status', 'cancellation_reason'])
     ) THEN
    RAISE EXCEPTION 'GUEST_CANCELLATION_FIELDS_FORBIDDEN' USING ERRCODE = '42501';
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
          FROM public.events e
          JOIN public.staff_assignments sa
            ON sa.organizer_id = e.organizer_id
          WHERE e.id = event_id
            AND sa.staff_id = auth.uid()
            AND sa.status = 'active'
            AND (sa.event_id = e.id OR sa.event_id IS NULL)
            AND COALESCE(sa.permissions ->> 'can_generate', 'false') = 'true'
        )
      )
    )
  )
);

-- Keep blacklist reads available to authorized security scanners, but require
-- the separate can_block_guest permission for every blacklist mutation.
ALTER TABLE public.blacklist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Organizers/Staff Can Manage Blacklist" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist read authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist insert authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist update authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist delete authorized" ON public.blacklist;

CREATE POLICY "Sivox blacklist read authorized"
ON public.blacklist
FOR SELECT
TO authenticated
USING (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND (
        COALESCE(sa.permissions ->> 'can_scan', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
      )
  )
);

CREATE POLICY "Sivox blacklist insert authorized"
ON public.blacklist
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

CREATE POLICY "Sivox blacklist update authorized"
ON public.blacklist
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

CREATE POLICY "Sivox blacklist delete authorized"
ON public.blacklist
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

-- Staff may read event bookings only when their active assignment grants an
-- operational permission that needs booking visibility.
DROP POLICY IF EXISTS "Sivox authorized staff booking read" ON public.bookings;
CREATE POLICY "Sivox authorized staff booking read"
ON public.bookings
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.staff_assignments sa
      ON sa.organizer_id = e.organizer_id
    WHERE e.id = bookings.event_id
      AND sa.staff_id = auth.uid()
      AND sa.status = 'active'
      AND (sa.event_id = e.id OR sa.event_id IS NULL)
      AND (
        COALESCE(sa.permissions ->> 'can_scan', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_confirm_payment', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_confirm_booking', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_manage_guests', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_view_stats', 'false') = 'true'
      )
  )
);

-- Securely fan out booking-stage notifications. The caller can notify only
-- the guest, event owner, and active staff entitled to the corresponding task.
CREATE OR REPLACE FUNCTION public.send_booking_stage_notification(
  p_booking_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_notify_guest boolean DEFAULT TRUE,
  p_notify_organizer boolean DEFAULT TRUE,
  p_notify_staff boolean DEFAULT FALSE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_guest_id uuid;
  v_event_id uuid;
  v_organizer_id uuid;
  v_owner_id uuid;
  v_permission text;
  v_metadata jsonb;
  v_send_guest boolean := p_notify_guest;
  v_send_staff boolean := p_notify_staff;
BEGIN
  SELECT b.user_id, b.event_id, e.organizer_id, op.owner_id
  INTO v_guest_id, v_event_id, v_organizer_id, v_owner_id
  FROM public.bookings b
  JOIN public.events e ON e.id = b.event_id
  JOIN public.organizer_profiles op ON op.id = e.organizer_id
  WHERE b.id = p_booking_id;

  IF NOT FOUND OR auth.uid() IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOTIFICATION_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  v_metadata := COALESCE(p_metadata, '{}'::jsonb)
    || jsonb_build_object('booking_id', p_booking_id, 'event_id', v_event_id);

  IF auth.uid() = v_guest_id THEN
    -- A guest may notify only the event owner about their own booking.
    v_send_guest := FALSE;
    v_send_staff := FALSE;
    IF NOT p_notify_organizer THEN
      RETURN;
    END IF;
  ELSE
    v_permission := CASE p_type
      WHEN 'security' THEN 'can_scan'
      WHEN 'presence' THEN 'can_confirm_payment'
      WHEN 'booking' THEN 'can_confirm_booking'
      WHEN 'booking_cancel' THEN 'can_cancel'
      WHEN 'late' THEN 'can_mark_late'
      WHEN 'ejected' THEN 'can_eject_guest'
      ELSE 'can_scan'
    END;

    IF NOT public.has_event_staff_permission(v_event_id, v_permission) THEN
      RAISE EXCEPTION 'BOOKING_NOTIFICATION_NOT_AUTHORIZED' USING ERRCODE = '42501';
    END IF;

    IF p_type = 'late'
       AND NOT public.has_event_staff_permission(v_event_id, 'can_confirm_payment') THEN
      RAISE EXCEPTION 'BOOKING_NOTIFICATION_NOT_AUTHORIZED' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF v_send_guest AND v_guest_id IS DISTINCT FROM auth.uid() THEN
    INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
    VALUES (v_guest_id, p_title, p_body, p_type, v_metadata, FALSE);
  END IF;

  IF p_notify_organizer AND v_owner_id IS NOT NULL AND v_owner_id IS DISTINCT FROM auth.uid() THEN
    INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
    VALUES (v_owner_id, p_title, p_body, p_type, v_metadata, FALSE);
  END IF;

  IF v_send_staff THEN
    INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
    SELECT DISTINCT sa.staff_id, p_title, p_body, p_type, v_metadata, FALSE
    FROM public.staff_assignments sa
    WHERE sa.organizer_id = v_organizer_id
      AND sa.status = 'active'
      AND (sa.event_id = v_event_id OR sa.event_id IS NULL)
      AND sa.staff_id <> auth.uid()
      AND COALESCE(sa.permissions ->> v_permission, 'false') = 'true';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.send_booking_stage_notification(
  uuid, text, text, text, jsonb, boolean, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_booking_stage_notification(
  uuid, text, text, text, jsonb, boolean, boolean, boolean
) TO authenticated;

-- A guest may cancel only their own pending/approved booking. Staff cancellation
-- remains governed by the existing staff update policy and can_cancel trigger.
DROP POLICY IF EXISTS "Sivox guests can cancel own bookings" ON public.bookings;
CREATE POLICY "Sivox guests can cancel own bookings"
ON public.bookings
FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
  AND payment_status IN ('pending', 'pending_confirmation', 'confirmed')
)
WITH CHECK (
  user_id = auth.uid()
  AND payment_status = 'cancelled'
);

-- Ticket transfer is a single authenticated-owner operation. It also creates
-- the recipient notification in the same database transaction.
CREATE OR REPLACE FUNCTION public.transfer_booking_ticket(
  p_booking_id uuid,
  p_target_user_id uuid,
  p_title text,
  p_body text
)
RETURNS TABLE (event_id uuid, event_title text, target_user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_event_id uuid;
  v_event_title text;
  v_target_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_target_user_id IS NULL
     OR p_target_user_id = auth.uid()
     OR NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_target_user_id) THEN
    RAISE EXCEPTION 'BOOKING_TRANSFER_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('app.ticket_transfer', 'on', TRUE);

  UPDATE public.bookings b
  SET user_id = p_target_user_id
  WHERE b.id = p_booking_id
    AND b.user_id = auth.uid()
    AND b.payment_status IN ('pending', 'pending_confirmation', 'confirmed')
    AND COALESCE(b.security_cleared, FALSE) = FALSE
    AND COALESCE(b.payment_confirmed, FALSE) = FALSE
  RETURNING b.event_id, b.user_id
  INTO v_event_id, v_target_user_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT e.title INTO v_event_title
  FROM public.events e
  WHERE e.id = v_event_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, metadata, is_read
  )
  VALUES (
    v_target_user_id,
    p_title,
    p_body,
    'booking',
    jsonb_build_object('booking_id', p_booking_id, 'event_id', v_event_id),
    FALSE
  );

  RETURN QUERY SELECT v_event_id, v_event_title, v_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_booking_ticket(uuid, uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_booking_ticket(uuid, uuid, text, text)
  TO authenticated;
