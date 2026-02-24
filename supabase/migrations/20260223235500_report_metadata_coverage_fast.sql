CREATE OR REPLACE FUNCTION public.report_link_metadata_coverage(p_report_id UUID)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH reported AS (
    SELECT ri.island_code
    FROM public.discover_report_islands ri
    WHERE ri.report_id = p_report_id
      AND ri.status = 'reported'
  ),
  joined AS (
    SELECT r.island_code, m.title, m.image_url
    FROM reported r
    LEFT JOIN public.discover_link_metadata m
      ON m.link_code = r.island_code
  )
  SELECT jsonb_build_object(
    'reported_islands', COUNT(*)::int,
    'with_title', COUNT(*) FILTER (WHERE title IS NOT NULL AND title <> '')::int,
    'with_image_url', COUNT(*) FILTER (WHERE image_url IS NOT NULL AND image_url <> '')::int
  )
  FROM joined;
$$;
