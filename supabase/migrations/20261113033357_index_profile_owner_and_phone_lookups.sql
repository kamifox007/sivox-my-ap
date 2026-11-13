-- Index the ownership lookup used by organizer dashboards and profile loading.
CREATE INDEX IF NOT EXISTS idx_organizer_profiles_user_created_at
ON public.organizer_profiles (user_id, created_at DESC)
WHERE user_id IS NOT NULL;

-- Support the alternate phone column used by authenticated ticket-transfer matching.
CREATE INDEX IF NOT EXISTS idx_profiles_phone_number
ON public.profiles (phone_number)
WHERE phone_number IS NOT NULL;
