
-- Consolidated metadata pipeline stats (replaces 8 separate COUNT queries)
CREATE OR REPLACE FUNCTION public.get_metadata_pipeline_stats()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'total',          count(*),
    'with_title',     count(*) FILTER (WHERE title IS NOT NULL),
    'with_error',     count(*) FILTER (WHERE last_error IS NOT NULL AND title IS NULL),
    'pending_no_data',count(*) FILTER (WHERE title IS NULL AND last_error IS NULL),
    'locked',         count(*) FILTER (WHERE locked_at IS NOT NULL),
    'due_now',        count(*) FILTER (WHERE next_due_at <= now()),
    'islands',        count(*) FILTER (WHERE link_code_type = 'island'),
    'collections',    count(*) FILTER (WHERE link_code_type = 'collection')
  )
  FROM discover_link_metadata;
$$;

-- Consolidated census stats (replaces 5+ separate COUNT queries)
CREATE OR REPLACE FUNCTION public.get_census_stats()
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'total_islands',    count(*),
    'reported',         count(*) FILTER (WHERE last_status = 'reported'),
    'suppressed',       count(*) FILTER (WHERE last_status = 'suppressed'),
    'with_title',       count(*) FILTER (WHERE title IS NOT NULL AND title != ''),
    'with_image',       count(*) FILTER (WHERE image_url IS NOT NULL AND image_url != ''),
    'unique_creators',  count(DISTINCT creator_code) FILTER (WHERE creator_code IS NOT NULL)
  )
  FROM discover_islands_cache;
$$;

-- Grant execute to anon/authenticated/service_role
GRANT EXECUTE ON FUNCTION public.get_metadata_pipeline_stats() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_census_stats() TO anon, authenticated, service_role;
