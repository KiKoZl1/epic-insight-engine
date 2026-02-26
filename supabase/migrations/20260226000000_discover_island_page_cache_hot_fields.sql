ALTER TABLE public.discover_island_page_cache
  ADD COLUMN IF NOT EXISTS last_accessed_at timestamptz,
  ADD COLUMN IF NOT EXISTS hit_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_refresh_error text;

UPDATE public.discover_island_page_cache
SET last_accessed_at = COALESCE(last_accessed_at, updated_at, as_of, now())
WHERE last_accessed_at IS NULL;

ALTER TABLE public.discover_island_page_cache
  ALTER COLUMN last_accessed_at SET DEFAULT now(),
  ALTER COLUMN last_accessed_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS discover_island_page_cache_last_accessed_idx
  ON public.discover_island_page_cache (last_accessed_at DESC);

CREATE INDEX IF NOT EXISTS discover_island_page_cache_updated_at_idx
  ON public.discover_island_page_cache (updated_at ASC);
