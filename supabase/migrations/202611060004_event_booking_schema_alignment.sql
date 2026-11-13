-- SivoX migration 4: additive schema alignment.
-- Existing end_time is TIMESTAMPTZ; preserve its live type.
ALTER TABLE public.organizer_profiles
  ADD COLUMN IF NOT EXISTS business_type TEXT DEFAULT 'club';

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS end_date TEXT,
  ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_urgent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS perk_granted_by UUID REFERENCES auth.users(id);

ALTER TABLE public.support_requests
  ADD COLUMN IF NOT EXISTS user_email TEXT,
  ADD COLUMN IF NOT EXISTS user_name TEXT;