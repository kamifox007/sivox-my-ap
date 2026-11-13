-- Return follower contact details only to the verified owner of the organizer profile.
-- This replaces the client-side join that attempted to read protected profile phone fields.

CREATE OR REPLACE FUNCTION private.get_organizer_audience_internal(
  p_organizer_id UUID
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT
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
    f.user_id,
    p.full_name,
    p.avatar_url,
    COALESCE(p.phone, p.phone_number)
  FROM public.follows f
  LEFT JOIN public.profiles p ON p.id = f.user_id
  WHERE f.organizer_id = p_organizer_id
  ORDER BY f.created_at DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION private.get_organizer_audience_internal(UUID)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_organizer_audience_internal(UUID)
TO authenticated;

CREATE OR REPLACE FUNCTION public.get_organizer_audience(
  p_organizer_id UUID
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT *
  FROM private.get_organizer_audience_internal(p_organizer_id);
$$;

REVOKE ALL ON FUNCTION public.get_organizer_audience(UUID)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organizer_audience(UUID)
TO authenticated;
