-- SivoX migration 3: identity and staff security.
-- Never trust role values in user-editable raw_user_meta_data.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
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

  profile_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone');

  INSERT INTO public.profiles (
    id, full_name, phone, phone_number, avatar_url, role, country_code
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
    profile_phone,
    COALESCE(NEW.raw_user_meta_data->>'phone_number', profile_phone),
    NEW.raw_user_meta_data->>'avatar_url',
    'attendee',
    COALESCE(NEW.raw_user_meta_data->>'country_code', 'DZ')
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone_number = COALESCE(EXCLUDED.phone_number, public.profiles.phone_number),
    avatar_url = EXCLUDED.avatar_url,
    country_code = EXCLUDED.country_code;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_user_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  UPDATE public.profiles
  SET full_name = COALESCE(NEW.raw_user_meta_data->>'full_name', full_name),
      avatar_url = COALESCE(NEW.raw_user_meta_data->>'avatar_url', avatar_url),
      phone_number = COALESCE(NEW.raw_user_meta_data->>'phone_number', NEW.phone, phone_number),
      phone = COALESCE(NEW.phone, phone),
      country_code = COALESCE(NEW.raw_user_meta_data->>'country_code', country_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_self_role_escalation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  jwt_role TEXT := COALESCE(current_setting('request.jwt.claim.role', TRUE), '');
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role')
     AND jwt_role <> 'service_role' THEN
    RAISE EXCEPTION 'PROFILE_ROLE_CHANGE_FORBIDDEN'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_profile_role ON public.profiles;
CREATE TRIGGER protect_profile_role
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.prevent_self_role_escalation();

CREATE OR REPLACE FUNCTION public.protect_staff_assignment_updates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  is_owner BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.organizer_profiles op
    WHERE op.id = OLD.organizer_id AND op.user_id = auth.uid()
  ) INTO is_owner;

  IF auth.uid() = OLD.staff_id AND NOT is_owner THEN
    IF OLD.status <> 'pending'
       OR NEW.status NOT IN ('active', 'declined')
       OR (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
      RAISE EXCEPTION 'STAFF_ASSIGNMENT_UPDATE_FORBIDDEN'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_staff_assignment_update ON public.staff_assignments;
CREATE TRIGGER protect_staff_assignment_update
BEFORE UPDATE ON public.staff_assignments
FOR EACH ROW
EXECUTE FUNCTION public.protect_staff_assignment_updates();

-- Lock down internal trigger functions; they are invoked by their owning triggers.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_self_role_escalation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_staff_assignment_updates() FROM PUBLIC, anon, authenticated;