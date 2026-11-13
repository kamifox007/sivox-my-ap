-- Keep legacy blocks fields and the current Flutter fields synchronized.
-- This preserves old rows/clients while allowing BlockService to write
-- user_id and blocked_organizer_id.
CREATE OR REPLACE FUNCTION public.sync_block_compat_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := NEW.blocker_id;
  ELSIF NEW.blocker_id IS NULL THEN
    NEW.blocker_id := NEW.user_id;
  ELSIF NEW.blocker_id IS DISTINCT FROM NEW.user_id THEN
    RAISE EXCEPTION 'BLOCK_OWNER_ID_MISMATCH' USING ERRCODE = '42501';
  END IF;

  IF NEW.blocked_organizer_id IS NULL
     AND NEW.blocked_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    NEW.blocked_organizer_id := NEW.blocked_id::UUID;
  ELSIF NEW.blocked_organizer_id IS NOT NULL AND NEW.blocked_id IS NULL THEN
    NEW.blocked_id := NEW.blocked_organizer_id::TEXT;
  ELSIF NEW.blocked_organizer_id IS NOT NULL
        AND NEW.blocked_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND NEW.blocked_organizer_id IS DISTINCT FROM NEW.blocked_id::UUID THEN
    RAISE EXCEPTION 'BLOCK_TARGET_ID_MISMATCH' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_block_compat_columns() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sync_block_compat_columns ON public.blocks;
CREATE TRIGGER sync_block_compat_columns
BEFORE INSERT OR UPDATE ON public.blocks
FOR EACH ROW
EXECUTE FUNCTION public.sync_block_compat_columns();