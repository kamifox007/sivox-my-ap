-- SivoX migration 6: support request form compatibility.
ALTER TABLE public.support_requests
  ADD COLUMN IF NOT EXISTS user_email TEXT,
  ADD COLUMN IF NOT EXISTS user_name TEXT;

ALTER TABLE public.support_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Insert Support Requests" ON public.support_requests;
DROP POLICY IF EXISTS "Support requests can be submitted" ON public.support_requests;
DROP POLICY IF EXISTS support_requests_insert ON public.support_requests;

CREATE POLICY support_requests_insert
ON public.support_requests
FOR INSERT TO anon, authenticated
WITH CHECK (
  user_id IS NULL OR user_id = (SELECT auth.uid())
);

DROP POLICY IF EXISTS "Read Own Support Requests" ON public.support_requests;
DROP POLICY IF EXISTS support_requests_select_own ON public.support_requests;

CREATE POLICY support_requests_select_own
ON public.support_requests
FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()));

REVOKE ALL ON public.support_requests FROM PUBLIC;
REVOKE ALL ON public.support_requests FROM anon;
GRANT INSERT ON public.support_requests TO anon, authenticated;
GRANT SELECT ON public.support_requests TO authenticated;