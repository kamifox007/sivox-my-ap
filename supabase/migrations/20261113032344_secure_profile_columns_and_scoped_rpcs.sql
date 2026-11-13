-- Harden public profile access and replace private-column client queries with scoped RPCs.
-- Authenticated users may only create attendee profiles for their own Auth UID.
-- Public clients can see profile display fields only; personal contact data and role
-- are exposed through purpose-built RPCs that verify the caller's authority.

DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = id
  AND role = 'attendee'
);

DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update
ON public.profiles
FOR UPDATE
TO authenticated
USING ((SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) = id);

-- Remove existing table-wide and column-level access from API roles.
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL (id, full_name, phone, phone_number, avatar_url, role, country_code, fcm_token, created_at)
ON TABLE public.profiles FROM PUBLIC, anon, authenticated;

-- Only public display fields may be selected directly.
GRANT SELECT (id, full_name, avatar_url)
ON TABLE public.profiles TO anon, authenticated;

-- Clients can create and edit their own non-privileged profile fields.
-- Role, FCM token, and created_at remain server-managed.
GRANT INSERT (id, full_name, phone, phone_number, avatar_url, country_code)
ON TABLE public.profiles TO authenticated;

GRANT UPDATE (id, full_name, phone, phone_number, avatar_url, country_code)
ON TABLE public.profiles TO authenticated;

-- Return the current user's database role without exposing the role column.
CREATE OR REPLACE FUNCTION public.get_my_profile_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT p.role FROM public.profiles p WHERE p.id = (SELECT auth.uid())),
    'attendee'
  );
$$;

REVOKE ALL ON FUNCTION public.get_my_profile_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_profile_role() TO authenticated;

-- Organizer-only staff search. Contact details are returned only to the owner
-- of the organizer profile whose staff directory is being managed.
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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  search_text TEXT := btrim(COALESCE(p_query, ''));
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

  IF length(search_text) < 2 THEN
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

REVOKE ALL ON FUNCTION public.search_staff_candidates(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_staff_candidates(UUID, TEXT) TO authenticated;

-- The staff directory includes phone numbers, so only an organizer owner can
-- retrieve staff assigned to their organizer profile.
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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
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

REVOKE ALL ON FUNCTION public.get_organizer_staff_directory(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organizer_staff_directory(UUID) TO authenticated;

-- Resolve a ticket transfer target only after confirming that the caller owns
-- the booking being transferred. Ambiguous phone matches return NULL.
CREATE OR REPLACE FUNCTION public.resolve_ticket_transfer_target(
  p_booking_id UUID,
  p_phone TEXT
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  target_phone TEXT := btrim(COALESCE(p_phone, ''));
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

  SELECT COUNT(*)::INTEGER
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

REVOKE ALL ON FUNCTION public.resolve_ticket_transfer_target(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_ticket_transfer_target(UUID, TEXT) TO authenticated;
