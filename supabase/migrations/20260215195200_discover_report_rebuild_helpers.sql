-- Helper RPCs for report rebuild without refetching Epic APIs.
-- These compute only the new "Links metadata" dependent rankings and coverage,
-- based on discover_report_islands + discover_link_metadata.

CREATE OR REPLACE FUNCTION public.report_link_metadata_coverage(p_report_id UUID)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'reported_islands', (SELECT COUNT(*) FROM public.discover_report_islands WHERE report_id = p_report_id AND status = 'reported'),
    'with_title', (
      SELECT COUNT(*)
      FROM public.discover_report_islands ri
      JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
      WHERE ri.report_id = p_report_id AND ri.status = 'reported'
        AND m.title IS NOT NULL AND m.title <> ''
    ),
    'with_image_url', (
      SELECT COUNT(*)
      FROM public.discover_report_islands ri
      JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
      WHERE ri.report_id = p_report_id AND ri.status = 'reported'
        AND m.image_url IS NOT NULL AND m.image_url <> ''
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.report_new_islands_by_launch(
  p_report_id UUID,
  p_week_start DATE,
  p_week_end DATE,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  island_code TEXT,
  title TEXT,
  creator_code TEXT,
  published_at_epic TIMESTAMPTZ,
  created_at_epic TIMESTAMPTZ,
  week_plays BIGINT,
  week_unique BIGINT,
  week_peak_ccu_max BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH meta AS (
    SELECT
      ri.island_code,
      ri.week_plays,
      ri.week_unique,
      ri.week_peak_ccu_max,
      m.title,
      COALESCE(m.support_code, ri.creator_code) AS creator_code,
      m.published_at_epic,
      m.created_at_epic,
      COALESCE(m.published_at_epic, m.created_at_epic) AS launch_ts
    FROM public.discover_report_islands ri
    JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
    WHERE ri.report_id = p_report_id AND ri.status = 'reported'
  )
  SELECT
    island_code,
    title,
    creator_code,
    published_at_epic,
    created_at_epic,
    week_plays::bigint,
    week_unique::bigint,
    week_peak_ccu_max::bigint
  FROM meta
  WHERE launch_ts >= (p_week_start::timestamptz)
    AND launch_ts < ((p_week_end + 1)::timestamptz)
  ORDER BY week_plays DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION public.report_new_islands_by_launch_count(
  p_report_id UUID,
  p_week_start DATE,
  p_week_end DATE
)
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH meta AS (
    SELECT COALESCE(m.published_at_epic, m.created_at_epic) AS launch_ts
    FROM public.discover_report_islands ri
    JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
    WHERE ri.report_id = p_report_id AND ri.status = 'reported'
  )
  SELECT COUNT(*)::bigint
  FROM meta
  WHERE launch_ts >= (p_week_start::timestamptz)
    AND launch_ts < ((p_week_end + 1)::timestamptz);
$$;

CREATE OR REPLACE FUNCTION public.report_most_updated_islands(
  p_report_id UUID,
  p_week_start DATE,
  p_week_end DATE,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  island_code TEXT,
  title TEXT,
  creator_code TEXT,
  updated_at_epic TIMESTAMPTZ,
  week_plays BIGINT,
  week_unique BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ri.island_code,
    COALESCE(m.title, ri.title) AS title,
    COALESCE(m.support_code, ri.creator_code) AS creator_code,
    m.updated_at_epic,
    ri.week_plays::bigint,
    ri.week_unique::bigint
  FROM public.discover_report_islands ri
  JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
  WHERE ri.report_id = p_report_id AND ri.status = 'reported'
    AND m.updated_at_epic >= (p_week_start::timestamptz)
    AND m.updated_at_epic < ((p_week_end + 1)::timestamptz)
  ORDER BY m.updated_at_epic DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION public.report_dead_islands_by_unique_drop(
  p_report_id UUID,
  p_prev_report_id UUID,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  island_code TEXT,
  title TEXT,
  creator_code TEXT,
  prev_week_unique BIGINT,
  week_unique BIGINT,
  delta_unique BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH cur AS (
    SELECT ri.island_code, ri.week_unique, ri.title, ri.creator_code
    FROM public.discover_report_islands ri
    WHERE ri.report_id = p_report_id AND ri.status = 'reported'
  ),
  prev AS (
    SELECT ri.island_code, ri.week_unique
    FROM public.discover_report_islands ri
    WHERE ri.report_id = p_prev_report_id AND ri.status = 'reported'
  )
  SELECT
    c.island_code,
    COALESCE(m.title, c.title) AS title,
    COALESCE(m.support_code, c.creator_code) AS creator_code,
    p.week_unique::bigint AS prev_week_unique,
    c.week_unique::bigint AS week_unique,
    (c.week_unique - p.week_unique)::bigint AS delta_unique
  FROM cur c
  JOIN prev p ON p.island_code = c.island_code
  LEFT JOIN public.discover_link_metadata m ON m.link_code = c.island_code
  WHERE (p.week_unique >= 500) AND (c.week_unique < 500)
  ORDER BY (p.week_unique - c.week_unique) DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$$;
