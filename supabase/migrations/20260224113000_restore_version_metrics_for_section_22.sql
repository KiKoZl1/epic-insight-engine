-- Restore version-based ranking and enrichment for Section 22 (Most Updated Islands).

DROP FUNCTION IF EXISTS public.report_most_updated_islands(uuid, date, date, integer);

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
  category TEXT,
  week_plays BIGINT,
  week_unique BIGINT,
  updated_at_epic TIMESTAMPTZ,
  version INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH links_updated AS (
    SELECT
      m.link_code,
      m.title,
      m.support_code,
      m.updated_at_epic,
      m.version
    FROM public.discover_link_metadata m
    WHERE m.updated_at_epic IS NOT NULL
      AND m.updated_at_epic >= (p_week_start::timestamptz)
      AND m.updated_at_epic < ((p_week_end + 1)::timestamptz)
  )
  SELECT
    ri.island_code,
    COALESCE(lm.title, ri.title) AS title,
    COALESCE(lm.support_code, ri.creator_code) AS creator_code,
    ri.category,
    ri.week_plays::bigint,
    ri.week_unique::bigint,
    lm.updated_at_epic,
    lm.version
  FROM links_updated lm
  JOIN public.discover_report_islands ri
    ON ri.island_code = lm.link_code
  WHERE ri.report_id = p_report_id
    AND ri.status = 'reported'
  ORDER BY
    lm.version DESC NULLS LAST,
    lm.updated_at_epic DESC NULLS LAST,
    ri.week_plays DESC
  LIMIT GREATEST(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION public.report_version_enrichment(p_report_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH ri AS (
    SELECT island_code
    FROM public.discover_report_islands
    WHERE report_id = p_report_id
      AND status = 'reported'
  ),
  versions AS (
    SELECT lm.version
    FROM ri
    JOIN public.discover_link_metadata lm
      ON lm.link_code = ri.island_code
    WHERE lm.version IS NOT NULL
  ),
  dist AS (
    SELECT
      CASE
        WHEN v.version = 1 THEN 'v1'
        WHEN v.version BETWEEN 2 AND 5 THEN 'v2-5'
        WHEN v.version BETWEEN 6 AND 10 THEN 'v6-10'
        WHEN v.version BETWEEN 11 AND 20 THEN 'v11-20'
        ELSE 'v21+'
      END AS tier,
      COUNT(*)::int AS count_value
    FROM versions v
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'avgVersion', COALESCE((SELECT ROUND(AVG(version)::numeric, 1) FROM versions), 0),
    'islandsWithVersion5Plus', COALESCE((SELECT COUNT(*)::int FROM versions WHERE version >= 5), 0),
    'totalWithVersion', COALESCE((SELECT COUNT(*)::int FROM versions), 0),
    'versionDistribution',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object('tier', d.tier, 'count', d.count_value)
          ORDER BY CASE d.tier
            WHEN 'v1' THEN 1
            WHEN 'v2-5' THEN 2
            WHEN 'v6-10' THEN 3
            WHEN 'v11-20' THEN 4
            ELSE 5
          END
        )
        FROM dist d
      ), '[]'::jsonb)
  );
$$;
