-- Lookup AI cache (3h TTL)

CREATE TABLE IF NOT EXISTS public.discover_lookup_ai_cache (
  id bigserial PRIMARY KEY,
  primary_code text NOT NULL,
  compare_code text NOT NULL DEFAULT '',
  locale text NOT NULL DEFAULT 'pt-BR',
  window_days integer NOT NULL DEFAULT 7 CHECK (window_days >= 1 AND window_days <= 90),
  payload_fingerprint text NOT NULL,
  response_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  hit_count integer NOT NULL DEFAULT 0 CHECK (hit_count >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS discover_lookup_ai_cache_key_uidx
  ON public.discover_lookup_ai_cache (primary_code, compare_code, locale, window_days, payload_fingerprint);

CREATE INDEX IF NOT EXISTS discover_lookup_ai_cache_expires_idx
  ON public.discover_lookup_ai_cache (expires_at);

ALTER TABLE public.discover_lookup_ai_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'discover_lookup_ai_cache'
      AND policyname = 'all_discover_lookup_ai_cache_service_role'
  ) THEN
    CREATE POLICY all_discover_lookup_ai_cache_service_role
      ON public.discover_lookup_ai_cache
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
