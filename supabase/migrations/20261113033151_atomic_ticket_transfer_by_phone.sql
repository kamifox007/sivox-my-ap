-- Replace target-ID lookup with an atomic phone-based transfer.
-- The caller never receives the matched user's UUID; authorization, matching,
-- booking mutation and recipient notification happen in one transaction.

CREATE OR REPLACE FUNCTION private.transfer_booking_ticket_by_phone_internal(
  p_booking_id UUID,
  p_phone TEXT,
  p_title TEXT,
  p_body TEXT
)
RETURNS TABLE(event_id UUID, event_title TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_phone TEXT := pg_catalog.btrim(COALESCE(p_phone, ''));
  v_match_count INTEGER;
  v_target_user_id UUID;
  v_event_id UUID;
  v_event_title TEXT;
BEGIN
  IF auth.uid() IS NULL OR v_phone = '' THEN
    RAISE EXCEPTION 'BOOKING_TRANSFER_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.id = p_booking_id
      AND b.user_id = auth.uid()
      AND b.payment_status IN ('pending', 'pending_confirmation', 'confirmed')
      AND COALESCE(b.security_cleared, FALSE) = FALSE
      AND COALESCE(b.payment_confirmed, FALSE) = FALSE
  ) THEN
    RETURN;
  END IF;

  SELECT pg_catalog.count(*)::INTEGER
  INTO v_match_count
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (p.phone = v_phone OR p.phone_number = v_phone);

  -- Reject ambiguous numbers instead of choosing an arbitrary account.
  IF v_match_count <> 1 THEN
    RETURN;
  END IF;

  SELECT p.id
  INTO v_target_user_id
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (p.phone = v_phone OR p.phone_number = v_phone)
  LIMIT 1
  FOR KEY SHARE;

  IF v_target_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Preserve the database trigger's explicitly authorized transfer path.
  PERFORM pg_catalog.set_config('app.sivox_ticket_transfer', 'on', TRUE);

  UPDATE public.bookings b
  SET user_id = v_target_user_id
  WHERE b.id = p_booking_id
    AND b.user_id = auth.uid()
    AND b.payment_status IN ('pending', 'pending_confirmation', 'confirmed')
    AND COALESCE(b.security_cleared, FALSE) = FALSE
    AND COALESCE(b.payment_confirmed, FALSE) = FALSE
  RETURNING b.event_id
  INTO v_event_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT e.title
  INTO v_event_title
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
    pg_catalog.jsonb_build_object(
      'booking_id', p_booking_id,
      'event_id', v_event_id
    ),
    FALSE
  );

  RETURN QUERY SELECT v_event_id, v_event_title;
END;
$$;

REVOKE ALL ON FUNCTION private.transfer_booking_ticket_by_phone_internal(UUID, TEXT, TEXT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.transfer_booking_ticket_by_phone_internal(UUID, TEXT, TEXT, TEXT)
TO authenticated;

CREATE OR REPLACE FUNCTION public.transfer_booking_ticket_by_phone(
  p_booking_id UUID,
  p_phone TEXT,
  p_title TEXT,
  p_body TEXT
)
RETURNS TABLE(event_id UUID, event_title TEXT)
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT *
  FROM private.transfer_booking_ticket_by_phone_internal(
    p_booking_id, p_phone, p_title, p_body
  );
$$;

REVOKE ALL ON FUNCTION public.transfer_booking_ticket_by_phone(UUID, TEXT, TEXT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_booking_ticket_by_phone(UUID, TEXT, TEXT, TEXT)
TO authenticated;

DROP FUNCTION IF EXISTS public.resolve_ticket_transfer_target(UUID, TEXT);
DROP FUNCTION IF EXISTS private.resolve_ticket_transfer_target_internal(UUID, TEXT);
