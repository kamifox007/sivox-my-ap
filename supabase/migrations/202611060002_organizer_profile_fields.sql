-- Organizer profile fields consumed by the Flutter app.
-- Apply this additive migration to the Supabase database before deploying the app.
-- It does not drop or rewrite existing data.

ALTER TABLE public.organizer_profiles
  ADD COLUMN IF NOT EXISTS name TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS business_type TEXT DEFAULT 'club';

UPDATE public.organizer_profiles
SET business_type = 'club'
WHERE business_type IS NULL;

DROP POLICY IF EXISTS "Organizer Profile Owner Insert" ON public.organizer_profiles;
CREATE POLICY "Organizer Profile Owner Insert"
ON public.organizer_profiles
FOR INSERT
TO authenticated
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Organizer Profile Owner Update" ON public.organizer_profiles;
CREATE POLICY "Organizer Profile Owner Update"
ON public.organizer_profiles
FOR UPDATE
TO authenticated
USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());
