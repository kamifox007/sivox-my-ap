-- SivoX migration 2: organizer profile compatibility.
-- name and avatar_url already exist in the live schema.
ALTER TABLE public.organizer_profiles
  ADD COLUMN IF NOT EXISTS business_type TEXT DEFAULT 'club';

UPDATE public.organizer_profiles
SET business_type = 'club'
WHERE business_type IS NULL;

ALTER TABLE public.organizer_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_insert ON public.organizer_profiles;
DROP POLICY IF EXISTS org_update ON public.organizer_profiles;
DROP POLICY IF EXISTS org_delete ON public.organizer_profiles;
DROP POLICY IF EXISTS "Organizer Profile Owner Insert" ON public.organizer_profiles;
DROP POLICY IF EXISTS "Organizer Profile Owner Update" ON public.organizer_profiles;

CREATE POLICY org_insert
ON public.organizer_profiles
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY org_update
ON public.organizer_profiles
FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY org_delete
ON public.organizer_profiles
FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.organizer_profiles TO authenticated;