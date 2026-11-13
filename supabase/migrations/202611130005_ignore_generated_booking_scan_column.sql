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
       OR (to_jsonb(NEW) - ARRAY['payment_status', 'cancellation_reason'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['payment_status', 'cancellation_reason']) THEN
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