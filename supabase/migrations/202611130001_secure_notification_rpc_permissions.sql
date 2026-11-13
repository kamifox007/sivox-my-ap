-- SivoX migration 9: secure notification RPCs retained from the production setup.
-- The previous functions were SECURITY DEFINER and accepted arbitrary recipient
-- IDs without verifying that the caller owned the organizer or its staff team.

CREATE OR REPLACE FUNCTION public.send_organizer_notification(
  p_organizer_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT DEFAULT 'announcement',
  p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = p_organizer_id
      AND op.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only the organizer owner may notify followers.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
  SELECT f.user_id, p_title, p_body, p_type, COALESCE(p_metadata, '{}'::JSONB), FALSE
  FROM public.follows f
  WHERE f.organizer_id = p_organizer_id
    AND COALESCE(f.notifications_enabled, TRUE) = TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_staff_notification(
  p_staff_id UUID,
  p_organizer_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT DEFAULT 'staff_mission',
  p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.organizer_profiles op
       WHERE op.id = p_organizer_id
         AND op.user_id = auth.uid()
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.staff_assignments sa
       WHERE sa.organizer_id = p_organizer_id
         AND sa.staff_id = p_staff_id
         AND sa.status = 'active'
     ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only an organizer may notify active assigned staff.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, metadata, is_read)
  VALUES (
    p_staff_id, p_title, p_body, p_type,
    COALESCE(p_metadata, '{}'::JSONB), FALSE
  );
END;
$$;

-- Keep event view increments available to the public feed but use a fixed
-- search_path. This is SECURITY INVOKER, not a privileged RPC.
CREATE OR REPLACE FUNCTION public.increment_event_views(row_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.events
  SET view_count = COALESCE(view_count, 0) + 1
  WHERE id = row_id;
END;
$$;

-- This event-trigger function is internal, not a Data API endpoint.
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.send_organizer_notification(UUID, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_staff_notification(UUID, UUID, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.send_organizer_notification(UUID, TEXT, TEXT, TEXT, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_staff_notification(UUID, UUID, TEXT, TEXT, TEXT, JSONB)
  TO authenticated;