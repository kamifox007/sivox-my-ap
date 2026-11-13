-- Keep profile phone fields synchronized only from Supabase Auth's verified phone.
-- Client metadata is user-editable, so raw_user_meta_data.phone* is never a source
-- for contact matching, audience directories, or ticket-transfer resolution.

REVOKE INSERT (phone, phone_number)
ON TABLE public.profiles FROM authenticated;
REVOKE UPDATE (phone, phone_number)
ON TABLE public.profiles FROM authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $function$
DECLARE
  email_domain TEXT;
  profile_phone TEXT;
BEGIN
  IF NEW.email IS NOT NULL THEN
    email_domain := lower(split_part(NEW.email, '@', 2));
    IF email_domain IN (
      'yopmail.com', 'mailinator.com', 'tempmail.com', '10minutemail.com',
      'sharklasers.com', 'guerrillamail.com', 'getnada.com', 'dispostable.com'
    ) THEN
      RAISE EXCEPTION 'DISPOSABLE_EMAIL_BLOCKED: Temporary email addresses are not allowed.';
    END IF;
  END IF;

  -- Supabase Auth phone is only populated after phone verification.
  -- Ignore raw_user_meta_data.phone and raw_user_meta_data.phone_number.
  profile_phone := NEW.phone;

  INSERT INTO public.profiles (
    id, full_name, phone, phone_number, avatar_url, role, country_code
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
    profile_phone,
    profile_phone,
    NEW.raw_user_meta_data->>'avatar_url',
    'attendee',
    COALESCE(NEW.raw_user_meta_data->>'country_code', 'DZ')
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    phone = EXCLUDED.phone,
    phone_number = EXCLUDED.phone_number,
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    country_code = COALESCE(EXCLUDED.country_code, public.profiles.country_code);

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_user_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $function$
BEGIN
  UPDATE public.profiles
  SET full_name = COALESCE(NEW.raw_user_meta_data->>'full_name', full_name),
      avatar_url = COALESCE(NEW.raw_user_meta_data->>'avatar_url', avatar_url),
      phone = NEW.phone,
      phone_number = NEW.phone,
      country_code = COALESCE(NEW.raw_user_meta_data->>'country_code', country_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$function$;

-- Clear unverified/stale profile numbers and use only the Auth phone value.
UPDATE public.profiles p
SET phone = u.phone,
    phone_number = u.phone
FROM auth.users u
WHERE u.id = p.id
  AND (
    p.phone IS DISTINCT FROM u.phone
    OR p.phone_number IS DISTINCT FROM u.phone
  );

-- Bootstrap and refresh a missing/stale profile phone from the caller's Auth row.
-- This is an internal SECURITY DEFINER function in the non-exposed private schema.
CREATE OR REPLACE FUNCTION private.get_my_profile_role_internal()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_auth_phone TEXT;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED' USING ERRCODE = '42501';
  END IF;

  SELECT u.phone
  INTO v_auth_phone
  FROM auth.users u
  WHERE u.id = v_uid;

  UPDATE public.profiles p
  SET phone = v_auth_phone,
      phone_number = v_auth_phone
  WHERE p.id = v_uid
    AND (
      p.phone IS DISTINCT FROM v_auth_phone
      OR p.phone_number IS DISTINCT FROM v_auth_phone
    );

  SELECT p.role
  INTO v_role
  FROM public.profiles p
  WHERE p.id = v_uid;

  RETURN COALESCE(v_role, 'attendee');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_profile_role()
RETURNS TEXT
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.get_my_profile_role_internal();
$function$;
