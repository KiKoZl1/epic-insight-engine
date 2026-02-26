CREATE TABLE IF NOT EXISTS public.discover_island_page_cache (
  island_code text NOT NULL,
  region text NOT NULL,
  surface_name text NOT NULL,
  payload_json jsonb NOT NULL,
  as_of timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT discover_island_page_cache_pkey PRIMARY KEY (island_code, region, surface_name)
);

CREATE INDEX IF NOT EXISTS discover_island_page_cache_expires_idx
  ON public.discover_island_page_cache (expires_at);

ALTER TABLE public.discover_island_page_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'discover_island_page_cache'
      AND policyname = 'all_discover_island_page_cache_service_role'
  ) THEN
    CREATE POLICY all_discover_island_page_cache_service_role
      ON public.discover_island_page_cache
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END$$;
