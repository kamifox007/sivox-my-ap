-- Make support requests compatible with the Flutter support form, including guest submissions.
-- Stored for review in GitHub only; not executed against live Supabase.

ALTER TABLE public.support_requests
  ADD COLUMN IF NOT EXISTS user_email TEXT,
  ADD COLUMN IF NOT EXISTS user_name TEXT;

DROP POLICY IF EXISTS "Support requests can be submitted" ON public.support_requests;
CREATE POLICY "Support requests can be submitted"
ON public.support_requests
FOR INSERT
TO anon, authenticated
WITH CHECK (
  user_id IS NULL OR user_id = auth.uid()
);
