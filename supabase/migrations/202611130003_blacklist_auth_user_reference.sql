-- SivoX migration 12: blacklist subjects are Auth users, even when a
-- legacy account does not yet have a public.profiles row.
ALTER TABLE public.blacklist
  DROP CONSTRAINT IF EXISTS blacklist_user_id_fkey;

ALTER TABLE public.blacklist
  ADD CONSTRAINT blacklist_user_id_auth_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;