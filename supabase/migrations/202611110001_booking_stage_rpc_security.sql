-- SivoX migration 8: secure booking stages, blacklist, blocks compatibility,
-- rate limiting, capacity checks and notification RPCs.
-- This migration targets the live schema where organizer_profiles.user_id is
-- the owner column (there is no organizer_profiles.owner_id).

-- ---------------------------------------------------------------------------
-- Permission helper: organizer owner or active assigned staff with a named flag.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_event_staff_permission(
  p_event_id UUID,
  p_permission TEXT
)
RETURNS BOOLEAN
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

-- ---------------------------------------------------------------------------
-- Blacklist required by EnforcementService and its profiles:user_id relation.
-- Keep user_id nullable so historical phone-only entries remain possible.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blacklist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.organizer_profiles(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  phone_number TEXT,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT blacklist_club_user_unique UNIQUE (club_id, user_id)
);

ALTER TABLE public.blacklist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizers/Staff Can Manage Blacklist" ON public.blacklist;
DROP POLICY IF EXISTS "Users Can Read Own Blacklist Status" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist read authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist insert authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist update authorized" ON public.blacklist;
DROP POLICY IF EXISTS "Sivox blacklist delete authorized" ON public.blacklist;

CREATE POLICY "Sivox blacklist read authorized"
ON public.blacklist
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND (
        COALESCE(sa.permissions ->> 'can_scan', 'false') = 'true'
        OR COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
      )
  )
);

CREATE POLICY "Sivox blacklist insert authorized"
ON public.blacklist
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

CREATE POLICY "Sivox blacklist update authorized"
ON public.blacklist
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

CREATE POLICY "Sivox blacklist delete authorized"
ON public.blacklist
FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = club_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.staff_assignments sa
    WHERE sa.organizer_id = club_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_block_guest', 'false') = 'true'
  )
);

REVOKE ALL ON public.blacklist FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.blacklist TO authenticated;

-- ---------------------------------------------------------------------------
-- Existing blocks table has blocker_id / blocked_id. Add the current Flutter
-- service's fields without dropping or rewriting the legacy columns.
-- ---------------------------------------------------------------------------
ALTER TABLE public.blocks
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS blocked_organizer_id UUID
    REFERENCES public.organizer_profiles(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS blocks_user_organizer_compat_unique
ON public.blocks(user_id, blocked_organizer_id)
WHERE user_id IS NOT NULL AND blocked_organizer_id IS NOT NULL;

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS blocks_all ON public.blocks;
DROP POLICY IF EXISTS blocks_select ON public.blocks;
DROP POLICY IF EXISTS blocks_insert ON public.blocks;
DROP POLICY IF EXISTS blocks_delete ON public.blocks;

CREATE POLICY blocks_all
ON public.blocks
FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

REVOKE ALL ON public.blocks FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.blocks TO authenticated;

-- ---------------------------------------------------------------------------
-- Make ejected a valid booking state; it is used by EnforcementService.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_payment_status_check;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_payment_status_check
  CHECK (
    payment_status = ANY (
      ARRAY[
        'pending'::TEXT,
        'pending_confirmation'::TEXT,
        'confirmed'::TEXT,
        'used'::TEXT,
        'late_accepted'::TEXT,
        'cancelled'::TEXT,
        'ejected'::TEXT
      ]
    )
  );

-- ---------------------------------------------------------------------------
-- Replace permissive legacy booking policies. RLS and the transition trigger
-- together prevent direct writes to protected booking fields.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bookings_insert ON public.bookings;
DROP POLICY IF EXISTS bookings_select ON public.bookings;
DROP POLICY IF EXISTS bookings_update ON public.bookings;
DROP POLICY IF EXISTS "Users can create own bookings" ON public.bookings;
DROP POLICY IF EXISTS "Sivox authorized staff booking read" ON public.bookings;
DROP POLICY IF EXISTS "Sivox guests can cancel own bookings" ON public.bookings;

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
          JOIN public.staff_assignments sa ON sa.organizer_id = e.organizer_id
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

CREATE POLICY bookings_select
ON public.bookings
FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR public.has_event_staff_permission(event_id, 'can_confirm_booking')
  OR public.has_event_staff_permission(event_id, 'can_scan')
  OR public.has_event_staff_permission(event_id, 'can_confirm_payment')
  OR public.has_event_staff_permission(event_id, 'can_manage_guests')
  OR public.has_event_staff_permission(event_id, 'can_view_stats')
  OR public.has_event_staff_permission(event_id, 'can_cancel')
  OR public.has_event_staff_permission(event_id, 'can_eject_guest')
);

CREATE POLICY bookings_update
ON public.bookings
FOR UPDATE TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR public.has_event_staff_permission(event_id, 'can_confirm_booking')
  OR public.has_event_staff_permission(event_id, 'can_scan')
  OR public.has_event_staff_permission(event_id, 'can_confirm_payment')
  OR public.has_event_staff_permission(event_id, 'can_manage_guests')
  OR public.has_event_staff_permission(event_id, 'can_cancel')
  OR public.has_event_staff_permission(event_id, 'can_eject_guest')
)
WITH CHECK (
  user_id = (SELECT auth.uid())
  OR public.has_event_staff_permission(event_id, 'can_confirm_booking')
  OR public.has_event_staff_permission(event_id, 'can_scan')
  OR public.has_event_staff_permission(event_id, 'can_confirm_payment')
  OR public.has_event_staff_permission(event_id, 'can_manage_guests')
  OR public.has_event_staff_permission(event_id, 'can_cancel')
  OR public.has_event_staff_permission(event_id, 'can_eject_guest')
);

-- ---------------------------------------------------------------------------
-- Booking transition guard. It is SECURITY INVOKER: the trusted transfer RPC
-- runs under its definer role, while direct REST updates run as authenticated.
-- The custom GUC is accepted only together with a privileged current_user.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_booking_stage_transitions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_privileged BOOLEAN :=
    current_user IN ('postgres', 'supabase_admin', 'service_role');
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    IF NOT v_privileged
       OR current_setting('app.sivox_ticket_transfer', TRUE) IS DISTINCT FROM 'on'
       OR OLD.user_id IS DISTINCT FROM auth.uid()
       OR OLD.payment_status NOT IN ('pending', 'pending_confirmation', 'confirmed')
       OR COALESCE(OLD.security_cleared, FALSE)
       OR COALESCE(OLD.payment_confirmed, FALSE)
       OR (to_jsonb(NEW) - ARRAY['user_id', 'is_scanned']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['user_id', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_TRANSFER_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.event_id IS DISTINCT FROM OLD.event_id THEN
    RAISE EXCEPTION 'BOOKING_EVENT_REASSIGNMENT_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- The guest may change the guest count only while the reservation is pending.
  IF NEW.num_guests IS DISTINCT FROM OLD.num_guests THEN
    IF OLD.user_id IS DISTINCT FROM auth.uid()
       OR OLD.payment_status NOT IN ('pending', 'pending_confirmation')
       OR NEW.num_guests IS NULL OR NEW.num_guests < 1 OR NEW.num_guests > 10
       OR (to_jsonb(NEW) - ARRAY['num_guests', 'is_scanned']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['num_guests', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_GUEST_COUNT_UPDATE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Table assignment is optional metadata for an authorized operator.
  IF NEW.table_number IS DISTINCT FROM OLD.table_number THEN
    IF NOT (
      public.has_event_staff_permission(OLD.event_id, 'can_manage_guests')
      OR public.has_event_staff_permission(OLD.event_id, 'can_confirm_payment')
    )
    OR OLD.payment_status NOT IN ('used', 'late_accepted')
    OR (to_jsonb(NEW) - ARRAY['table_number', 'is_scanned']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['table_number', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_TABLE_ASSIGNMENT_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Organizer/staff perk grants may update only the two perk fields.
  IF NEW.applied_perk IS DISTINCT FROM OLD.applied_perk
     OR NEW.perk_granted_by IS DISTINCT FROM OLD.perk_granted_by THEN
    IF NOT public.has_event_staff_permission(OLD.event_id, 'can_manage_guests')
       OR (NEW.perk_granted_by IS NOT NULL AND NEW.perk_granted_by IS DISTINCT FROM auth.uid())
       OR (to_jsonb(NEW) - ARRAY['applied_perk', 'perk_granted_by', 'is_scanned'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['applied_perk', 'perk_granted_by', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_PERK_UPDATE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    IF NEW.perk_granted_by IS NULL THEN
      NEW.perk_granted_by := auth.uid();
    END IF;
    RETURN NEW;
  END IF;

  -- Approval is server-side only, through approve_event_booking().
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
     AND NEW.payment_status = 'confirmed' THEN
    IF NOT v_privileged
       OR OLD.payment_status NOT IN ('pending', 'pending_confirmation')
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_confirm_booking')
       OR (to_jsonb(NEW) - ARRAY['payment_status', 'is_scanned']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['payment_status', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_APPROVAL_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- First checkpoint: security clearance.
  IF NEW.security_cleared IS DISTINCT FROM OLD.security_cleared THEN
    IF NOT v_privileged
       OR NEW.security_cleared IS DISTINCT FROM TRUE
       OR OLD.payment_status <> 'confirmed'
       OR COALESCE(OLD.security_cleared, FALSE)
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_scan')
       OR (to_jsonb(NEW) - ARRAY['security_cleared', 'scanned_at_security', 'is_scanned'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['security_cleared', 'scanned_at_security', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_SECURITY_STAGE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Second checkpoint: manager payment confirmation and final admission.
  IF NEW.payment_confirmed IS DISTINCT FROM OLD.payment_confirmed
     OR NEW.confirmed_by_manager IS DISTINCT FROM OLD.confirmed_by_manager
     OR NEW.scanned_at_payment IS DISTINCT FROM OLD.scanned_at_payment
     OR NEW.payment_status IN ('used', 'late_accepted')
        AND NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
    IF NOT v_privileged
       OR OLD.payment_status <> 'confirmed'
       OR COALESCE(OLD.security_cleared, FALSE) IS DISTINCT FROM TRUE
       OR COALESCE(OLD.payment_confirmed, FALSE)
       OR NEW.payment_confirmed IS DISTINCT FROM TRUE
       OR NEW.payment_status NOT IN ('used', 'late_accepted')
       OR NEW.confirmed_by_manager IS DISTINCT FROM auth.uid()
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_confirm_payment')
       OR (
         NEW.payment_status = 'late_accepted'
         AND NOT public.has_event_staff_permission(OLD.event_id, 'can_mark_late')
       )
       OR (to_jsonb(NEW) - ARRAY[
            'payment_status', 'payment_confirmed', 'confirmed_by_manager',
            'scanned_at_payment', 'scanned_at', 'is_scanned'
          ]) IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY[
            'payment_status', 'payment_confirmed', 'confirmed_by_manager',
            'scanned_at_payment', 'scanned_at', 'is_scanned'
          ]) THEN
      RAISE EXCEPTION 'BOOKING_PAYMENT_STAGE_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Guest or authorized staff cancellation; only the reason and status change.
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
     AND NEW.payment_status = 'cancelled' THEN
    IF OLD.payment_status NOT IN ('pending', 'pending_confirmation', 'confirmed')
       OR NOT (
         OLD.user_id = auth.uid()
         OR public.has_event_staff_permission(OLD.event_id, 'can_cancel')
       )
       OR (to_jsonb(NEW) - ARRAY['payment_status', 'cancellation_reason', 'is_scanned'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['payment_status', 'cancellation_reason', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_CANCELLATION_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Ejection is a dedicated staff action, distinct from cancellation.
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
     AND NEW.payment_status = 'ejected' THEN
    IF OLD.payment_status IN ('cancelled', 'ejected')
       OR NOT public.has_event_staff_permission(OLD.event_id, 'can_eject_guest')
       OR (to_jsonb(NEW) - ARRAY['payment_status', 'cancellation_reason', 'is_scanned'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['payment_status', 'cancellation_reason', 'is_scanned']) THEN
      RAISE EXCEPTION 'BOOKING_EJECTION_FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'BOOKING_UPDATE_FIELDS_FORBIDDEN' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS enforce_booking_stage_transitions ON public.bookings;
CREATE TRIGGER enforce_booking_stage_transitions
BEFORE UPDATE ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.enforce_booking_stage_transitions();

-- ---------------------------------------------------------------------------

-- Atomic capacity validation. Lock the parent event row to serialize concurrent
-- inserts/guest-count changes for the same event and avoid overselling capacity.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_event_capacity_before_booking()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_max_capacity INTEGER;
  v_current_booked BIGINT := 0;
BEGIN
  SELECT e.max_capacity
  INTO v_max_capacity
  FROM public.events e
  WHERE e.id = NEW.event_id
  FOR UPDATE;

  IF NOT FOUND OR v_max_capacity IS NULL OR v_max_capacity <= 0
     OR NEW.payment_status IN ('cancelled', 'ejected') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(SUM(b.num_guests), 0)
  INTO v_current_booked
  FROM public.bookings b
  WHERE b.event_id = NEW.event_id
    AND b.payment_status NOT IN ('cancelled', 'ejected')
    AND (TG_OP = 'INSERT' OR b.id <> NEW.id);

  IF v_current_booked + COALESCE(NEW.num_guests, 1) > v_max_capacity THEN
    RAISE EXCEPTION 'EVENT_FULL: Capacity exceeded. Remaining spots: %.',
      GREATEST(v_max_capacity - v_current_booked, 0)
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_event_capacity ON public.bookings;
CREATE TRIGGER trigger_check_event_capacity
BEFORE INSERT OR UPDATE OF num_guests, event_id
ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.check_event_capacity_before_booking();

-- Serialize per-user rate checks to prevent concurrent requests bypassing limit.
CREATE OR REPLACE FUNCTION public.check_booking_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  row_count INTEGER;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 0));

    SELECT COUNT(*) INTO row_count
    FROM public.bookings b
    WHERE b.user_id = auth.uid()
      AND b.created_at > NOW() - INTERVAL '1 minute'
      AND b.payment_status NOT IN ('cancelled', 'ejected');

    IF row_count >= 10 THEN
      RAISE EXCEPTION 'RATE_LIMIT_EXCEEDED: Please wait before creating another booking.'
        USING ERRCODE = '54000';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_rate_limit_trigger ON public.bookings;
CREATE TRIGGER bookings_rate_limit_trigger
BEFORE INSERT ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.check_booking_rate_limit();

-- ---------------------------------------------------------------------------
-- Event report moderation trigger, with the compatible is_hidden column.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_hide_event_on_reports()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  report_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO report_count
  FROM public.event_reports
  WHERE event_id = NEW.event_id;

  IF report_count >= 20 THEN
    UPDATE public.events SET is_hidden = TRUE WHERE id = NEW.event_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_hide_event ON public.event_reports;
CREATE TRIGGER trigger_auto_hide_event
AFTER INSERT ON public.event_reports
FOR EACH ROW
EXECUTE FUNCTION public.auto_hide_event_on_reports();

-- Secure report creation and restrict report visibility to the reporter or
-- event owner/authorized staff.
ALTER TABLE public.event_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can create reports" ON public.event_reports;
DROP POLICY IF EXISTS "Users can view their own reports" ON public.event_reports;
DROP POLICY IF EXISTS "Anyone Can Submit Report" ON public.event_reports;
DROP POLICY IF EXISTS "Organizers/Staff Can See Reports" ON public.event_reports;
DROP POLICY IF EXISTS event_reports_insert ON public.event_reports;
DROP POLICY IF EXISTS event_reports_select ON public.event_reports;

CREATE POLICY event_reports_insert
ON public.event_reports
FOR INSERT TO authenticated
WITH CHECK (reporter_id = (SELECT auth.uid()));

CREATE POLICY event_reports_select
ON public.event_reports
FOR SELECT TO authenticated
USING (
  reporter_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizer_profiles op ON op.id = e.organizer_id
    WHERE e.id = event_id AND op.user_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT 1
    FROM public.staff_assignments sa
    WHERE sa.event_id = event_id
      AND sa.staff_id = (SELECT auth.uid())
      AND sa.status = 'active'
      AND COALESCE(sa.permissions ->> 'can_view_stats', 'false') = 'true'
  )
);

-- ---------------------------------------------------------------------------
-- Permission-checked booking RPCs used by BookingService.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_event_booking(p_booking_id UUID)
RETURNS TABLE (
  user_id UUID, event_id UUID, event_title TEXT, organizer_id UUID, user_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_event_id UUID;
  v_user_name TEXT;
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

CREATE OR REPLACE FUNCTION public.verify_booking_security_clearance(p_booking_id UUID)
RETURNS TABLE (
  user_id UUID, event_id UUID, event_title TEXT, organizer_id UUID, user_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_event_id UUID;
  v_user_name TEXT;
BEGIN
  UPDATE public.bookings b
  SET security_cleared = TRUE, scanned_at_security = NOW()
  WHERE b.id = p_booking_id
    AND b.payment_status = 'confirmed'
    AND COALESCE(b.security_cleared, FALSE) = FALSE
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

CREATE OR REPLACE FUNCTION public.confirm_booking_manager_payment(p_booking_id UUID)
RETURNS TABLE (
  user_id UUID, event_id UUID, event_title TEXT, organizer_id UUID, user_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_event_id UUID;
  v_user_name TEXT;
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
    AND COALESCE(b.payment_confirmed, FALSE) = FALSE
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

CREATE OR REPLACE FUNCTION public.accept_booking_late_entry(p_booking_id UUID)
RETURNS TABLE (
  user_id UUID, event_id UUID, event_title TEXT, organizer_id UUID, user_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_event_id UUID;
  v_user_name TEXT;
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
    AND COALESCE(b.payment_confirmed, FALSE) = FALSE
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

-- ---------------------------------------------------------------------------
-- Secure notification fan-out. Guests may notify only their own event owner;
-- staff/organizers require the permission matching the notification type.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_booking_stage_notification(
  p_booking_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_notify_guest BOOLEAN DEFAULT TRUE,
  p_notify_organizer BOOLEAN DEFAULT TRUE,
  p_notify_staff BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_guest_id UUID;
  v_event_id UUID;
  v_organizer_id UUID;
  v_owner_id UUID;
  v_permission TEXT;
  v_metadata JSONB;
  v_send_guest BOOLEAN := p_notify_guest;
  v_send_staff BOOLEAN := p_notify_staff;
BEGIN
  SELECT b.user_id, b.event_id, e.organizer_id, op.user_id
  INTO v_guest_id, v_event_id, v_organizer_id, v_owner_id
  FROM public.bookings b
  JOIN public.events e ON e.id = b.event_id
  JOIN public.organizer_profiles op ON op.id = e.organizer_id
  WHERE b.id = p_booking_id;

  IF NOT FOUND OR auth.uid() IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOTIFICATION_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  v_metadata := COALESCE(p_metadata, '{}'::JSONB)
    || jsonb_build_object('booking_id', p_booking_id, 'event_id', v_event_id);

  IF auth.uid() = v_guest_id THEN
    v_send_guest := FALSE;
    v_send_staff := FALSE;
    IF NOT p_notify_organizer THEN RETURN; END IF;
  ELSE
    v_permission := CASE p_type
      WHEN 'security' THEN 'can_scan'
      WHEN 'presence' THEN 'can_confirm_payment'
      WHEN 'booking' THEN 'can_confirm_booking'
      WHEN 'booking_cancel' THEN 'can_cancel'
      WHEN 'late' THEN 'can_mark_late'
      WHEN 'ejected' THEN 'can_eject_guest'
      WHEN 'milestone' THEN 'can_view_stats'
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

  IF p_notify_organizer
     AND v_owner_id IS NOT NULL
     AND v_owner_id IS DISTINCT FROM auth.uid() THEN
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

-- ---------------------------------------------------------------------------
-- Secure ticket transfer. The trigger accepts the transfer marker only while
-- executing this SECURITY DEFINER RPC (the client role cannot set current_user
-- to a privileged role).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transfer_booking_ticket(
  p_booking_id UUID,
  p_target_user_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS TABLE (event_id UUID, event_title TEXT, target_user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_event_id UUID;
  v_event_title TEXT;
  v_target_user_id UUID;
BEGIN
  IF auth.uid() IS NULL
     OR p_target_user_id IS NULL
     OR p_target_user_id = auth.uid()
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles p WHERE p.id = p_target_user_id
     ) THEN
    RAISE EXCEPTION 'BOOKING_TRANSFER_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('app.sivox_ticket_transfer', 'on', TRUE);

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
  FROM public.events e WHERE e.id = v_event_id;

  INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
  VALUES (
    v_target_user_id, p_title, p_body, 'booking',
    jsonb_build_object('booking_id', p_booking_id, 'event_id', v_event_id),
    FALSE
  );

  RETURN QUERY SELECT v_event_id, v_event_title, v_target_user_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Restrict direct notification inserts to the current user. Trusted RPCs above
-- run as their definer and can create notifications for the intended recipients.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS notifs_insert ON public.notifications;
DROP POLICY IF EXISTS notifications_insert_self ON public.notifications;

CREATE POLICY notifications_insert_self
ON public.notifications
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

-- ---------------------------------------------------------------------------
-- Explicit Data API privileges for the new public tables, with RLS retained.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON public.blacklist, public.blocks TO authenticated;
GRANT UPDATE, DELETE ON public.blacklist, public.blocks TO authenticated;
GRANT SELECT, INSERT ON public.event_reports TO authenticated;

-- Internal trigger functions must not be callable as public RPC endpoints.
REVOKE ALL ON FUNCTION public.enforce_booking_stage_transitions() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_event_capacity_before_booking() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_booking_rate_limit() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_hide_event_on_reports() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.approve_event_booking(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_booking_security_clearance(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_booking_manager_payment(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_booking_late_entry(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_booking_stage_notification(
  UUID, TEXT, TEXT, TEXT, JSONB, BOOLEAN, BOOLEAN, BOOLEAN
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transfer_booking_ticket(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.approve_event_booking(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_booking_security_clearance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_booking_manager_payment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_booking_late_entry(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_booking_stage_notification(
  UUID, TEXT, TEXT, TEXT, JSONB, BOOLEAN, BOOLEAN, BOOLEAN
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_booking_ticket(UUID, UUID, TEXT, TEXT) TO authenticated;