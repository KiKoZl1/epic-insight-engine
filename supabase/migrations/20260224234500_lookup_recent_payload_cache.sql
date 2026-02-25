-- Per-user full lookup payload cache (keep last 3 rows/user in edge function)

CREATE TABLE IF NOT EXISTS public.discover_lookup_recent (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  primary_code text NOT NULL,
  compare_code text NOT NULL DEFAULT '',
  primary_title text,
  compare_title text,
  payload_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  hit_count integer NOT NULL DEFAULT 0 CHECK (hit_count >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS discover_lookup_recent_key_uidx
  ON public.discover_lookup_recent (user_id, primary_code, compare_code);

CREATE INDEX IF NOT EXISTS discover_lookup_recent_user_access_idx
  ON public.discover_lookup_recent (user_id, last_accessed_at DESC);

ALTER TABLE public.discover_lookup_recent ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'discover_lookup_recent'
      AND policyname = 'all_discover_lookup_recent_service_role'
  ) THEN
    CREATE POLICY all_discover_lookup_recent_service_role
      ON public.discover_lookup_recent
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
