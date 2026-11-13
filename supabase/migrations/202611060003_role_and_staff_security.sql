-- Security hardening for account roles and staff invitations.
-- Review and apply to the intended Supabase project before deployment.
-- This migration is stored in GitHub only; it is NOT run against the live database.

-- Never accept a privileged profile role from user-editable auth metadata.
-- Existing profile roles are preserved on auth.users updates.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  email_domain TEXT;
BEGIN
  IF new.email IS NOT NULL THEN
    email_domain := split_part(new.email, '@', 2);
    IF email_domain IN (
      'yopmail.com', 'mailinator.com', 'tempmail.com', '10minutemail.com',
      'sharklasers.com', 'guerrillamail.com', 'getnada.com', 'dispostable.com'
    ) THEN
      RAISE EXCEPTION 'DISPOSABLE_EMAIL_BLOCKED: Registration using temporary/disposable email addresses is not allowed.';
    END IF;
  END IF;

  INSERT INTO public.profiles (id, full_name, avatar_url, role, phone)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url',
    'attendee',
    COALESCE(new.phone, new.raw_user_meta_data->>'phone')
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    avatar_url = EXCLUDED.avatar_url,
    phone = EXCLUDED.phone,
    updated_at = NOW();

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Users may edit their own profile details, but never grant themselves a role.
CREATE OR REPLACE FUNCTION public.prevent_self_role_escalation()
RETURNS trigger AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'PROFILE_ROLE_CHANGE_FORBIDDEN';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS protect_profile_role ON public.profiles;
CREATE TRIGGER protect_profile_role
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.prevent_self_role_escalation();

-- A staff member may only accept/decline their own pending invitation.
-- They cannot rewrite the organizer, event, staff identity, role or permissions.
CREATE OR REPLACE FUNCTION public.protect_staff_assignment_updates()
RETURNS trigger AS $$
BEGIN
  IF auth.uid() = OLD.staff_id
     AND NOT EXISTS (
       SELECT 1 FROM public.organizer_profiles op
       WHERE op.id = OLD.organizer_id AND op.owner_id = auth.uid()
     ) THEN
    IF NEW.staff_id IS DISTINCT FROM OLD.staff_id
       OR NEW.organizer_id IS DISTINCT FROM OLD.organizer_id
       OR NEW.event_id IS DISTINCT FROM OLD.event_id
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.permissions IS DISTINCT FROM OLD.permissions
       OR OLD.status <> 'pending'
       OR NEW.status NOT IN ('active', 'declined') THEN
      RAISE EXCEPTION 'STAFF_ASSIGNMENT_UPDATE_FORBIDDEN';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS protect_staff_assignment_update ON public.staff_assignments;
CREATE TRIGGER protect_staff_assignment_update
BEFORE UPDATE ON public.staff_assignments
FOR EACH ROW EXECUTE FUNCTION public.protect_staff_assignment_updates();
