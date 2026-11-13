-- Preserve the organizer-level follower perk used to prefill new event creation.
-- Other organizer profile field names are aligned to the existing schema in Flutter.
ALTER TABLE public.organizer_profiles
  ADD COLUMN IF NOT EXISTS follower_perk TEXT;
