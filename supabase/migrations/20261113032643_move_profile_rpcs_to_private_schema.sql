-- Keep RPC endpoints in the exposed public schema as SECURITY INVOKER wrappers.
-- Sensitive reads run in a non-exposed private schema, with caller and ownership
-- checks inside every SECURITY DEFINER implementation.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.get_my_profile_role_internal()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()),
    'attendee'
  );
$$;
REVOKE ALL ON FUNCTION private.get_my_profile_role_internal() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_my_profile_role_internal() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_profile_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.get_my_profile_role_internal();
$$;
REVOKE ALL ON FUNCTION public.get_my_profile_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_profile_role() TO authenticated;

CREATE OR REPLACE FUNCTION private.search_staff_candidates_internal(
  p_organizer_id UUID,
  p_query TEXT
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  phone TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  search_text TEXT := pg_catalog.btrim(COALESCE(p_query, ''));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = p_organizer_id
      AND op.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'ORGANIZER_ACCESS_DENIED' USING ERRCODE = '42501';
  END IF;

  IF pg_catalog.length(search_text) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    COALESCE(p.phone, p.phone_number),
    p.avatar_url
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (
      COALESCE(p.full_name, '') ILIKE '%' || search_text || '%'
      OR COALESCE(p.phone, p.phone_number, '') ILIKE '%' || search_text || '%'
    )
  ORDER BY p.full_name NULLS LAST
  LIMIT 5;
END;
$$;
REVOKE ALL ON FUNCTION private.search_staff_candidates_internal(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.search_staff_candidates_internal(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.search_staff_candidates(
  p_organizer_id UUID,
  p_query TEXT
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  phone TEXT,
  avatar_url TEXT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT * FROM private.search_staff_candidates_internal(p_organizer_id, p_query);
$$;
REVOKE ALL ON FUNCTION public.search_staff_candidates(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_staff_candidates(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION private.get_organizer_staff_directory_internal(
  p_organizer_id UUID
)
RETURNS TABLE (
  assignment_id UUID,
  staff_id UUID,
  full_name TEXT,
  phone TEXT,
  role TEXT,
  status TEXT,
  permissions JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organizer_profiles op
    WHERE op.id = p_organizer_id
      AND op.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'ORGANIZER_ACCESS_DENIED' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    sa.id,
    sa.staff_id,
    p.full_name,
    COALESCE(p.phone, p.phone_number),
    sa.role,
    sa.status,
    sa.permissions
  FROM public.staff_assignments sa
  LEFT JOIN public.profiles p ON p.id = sa.staff_id
  WHERE sa.organizer_id = p_organizer_id
  ORDER BY sa.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION private.get_organizer_staff_directory_internal(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_organizer_staff_directory_internal(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_organizer_staff_directory(
  p_organizer_id UUID
)
RETURNS TABLE (
  assignment_id UUID,
  staff_id UUID,
  full_name TEXT,
  phone TEXT,
  role TEXT,
  status TEXT,
  permissions JSONB
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT * FROM private.get_organizer_staff_directory_internal(p_organizer_id);
$$;
REVOKE ALL ON FUNCTION public.get_organizer_staff_directory(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organizer_staff_directory(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION private.resolve_ticket_transfer_target_internal(
  p_booking_id UUID,
  p_phone TEXT
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  target_phone TEXT := pg_catalog.btrim(COALESCE(p_phone, ''));
  match_count INTEGER;
  target_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF target_phone = '' OR NOT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.id = p_booking_id
      AND b.user_id = auth.uid()
  ) THEN
    RETURN NULL;
  END IF;

  SELECT pg_catalog.count(*)::INTEGER
  INTO match_count
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (p.phone = target_phone OR p.phone_number = target_phone);

  IF match_count <> 1 THEN
    RETURN NULL;
  END IF;

  SELECT p.id
  INTO target_id
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (p.phone = target_phone OR p.phone_number = target_phone)
  LIMIT 1;

  RETURN target_id;
END;
$$;
REVOKE ALL ON FUNCTION private.resolve_ticket_transfer_target_internal(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.resolve_ticket_transfer_target_internal(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_ticket_transfer_target(
  p_booking_id UUID,
  p_phone TEXT
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.resolve_ticket_transfer_target_internal(p_booking_id, p_phone);
$$;
REVOKE ALL ON FUNCTION public.resolve_ticket_transfer_target(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_ticket_transfer_target(UUID, TEXT) TO authenticated;
