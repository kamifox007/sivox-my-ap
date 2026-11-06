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
