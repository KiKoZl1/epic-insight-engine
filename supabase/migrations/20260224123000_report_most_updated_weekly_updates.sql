-- Add weekly updates metric to most-updated islands reporting.

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
  version INTEGER,
  weekly_updates INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH report_islands AS (
    SELECT
      ri.island_code,
      ri.title,
      ri.creator_code,
      ri.category,
      ri.week_plays,
      ri.week_unique
    FROM public.discover_report_islands ri
    WHERE ri.report_id = p_report_id
      AND ri.status = 'reported'
  ),
  links_updated AS (
    SELECT
      m.link_code,
      m.title,
      m.support_code,
      m.updated_at_epic,
      m.version
    FROM public.discover_link_metadata m
    JOIN report_islands ri
      ON ri.island_code = m.link_code
    WHERE m.updated_at_epic IS NOT NULL
      AND m.updated_at_epic >= (p_week_start::timestamptz)
      AND m.updated_at_epic < ((p_week_end + 1)::timestamptz)
  ),
  updates_week AS (
    SELECT
      e.link_code,
      COUNT(*)::int AS weekly_updates
    FROM public.discover_link_metadata_events e
    JOIN report_islands ri
      ON ri.island_code = e.link_code
    WHERE e.ts >= (p_week_start::timestamptz)
      AND e.ts < ((p_week_end + 1)::timestamptz)
      AND e.event_type IN ('epic_updated', 'version_changed')
    GROUP BY e.link_code
  )
  SELECT
    ri.island_code,
    COALESCE(lm.title, ri.title) AS title,
    COALESCE(lm.support_code, ri.creator_code) AS creator_code,
    ri.category,
    ri.week_plays::bigint,
    ri.week_unique::bigint,
    lm.updated_at_epic,
    lm.version,
    COALESCE(uw.weekly_updates, 0) AS weekly_updates
  FROM links_updated lm
  JOIN report_islands ri
    ON ri.island_code = lm.link_code
  LEFT JOIN updates_week uw
    ON uw.link_code = ri.island_code
  ORDER BY
    lm.version DESC NULLS LAST,
    COALESCE(uw.weekly_updates, 0) DESC,
    lm.updated_at_epic DESC NULLS LAST,
    ri.week_plays DESC
  LIMIT GREATEST(p_limit, 1);
$$;
