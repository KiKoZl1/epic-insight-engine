-- Performance optimizations for report generation and public report opening.
-- Full-data strategy: keep all report sections, reduce query cost with better plans.

-- ============================================================
-- 1) Indexes for link-metadata windowed queries
-- ============================================================
CREATE INDEX IF NOT EXISTS discover_link_metadata_published_link_idx
  ON public.discover_link_metadata (published_at_epic, link_code)
  WHERE published_at_epic IS NOT NULL;

CREATE INDEX IF NOT EXISTS discover_link_metadata_updated_link_idx
  ON public.discover_link_metadata (updated_at_epic DESC, link_code)
  WHERE updated_at_epic IS NOT NULL;

CREATE INDEX IF NOT EXISTS discover_link_metadata_launch_link_idx
  ON public.discover_link_metadata ((COALESCE(published_at_epic, created_at_epic)), link_code)
  WHERE COALESCE(published_at_epic, created_at_epic) IS NOT NULL;

CREATE INDEX IF NOT EXISTS discover_link_metadata_support_published_idx
  ON public.discover_link_metadata (support_code, published_at_epic)
  WHERE support_code IS NOT NULL AND published_at_epic IS NOT NULL;

CREATE INDEX IF NOT EXISTS discover_report_islands_report_status_code_idx
  ON public.discover_report_islands (report_id, status, island_code);

CREATE INDEX IF NOT EXISTS discovery_exposure_rollup_daily_date_type_link_panel_idx
  ON public.discovery_exposure_rollup_daily (date, link_code_type, link_code, panel_name);

-- ============================================================
-- 2) Faster helper RPCs (filter metadata first, then join report islands)
-- ============================================================
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
SET statement_timeout = '120s'
AS $$
  WITH links_in_window AS (
    SELECT
      m.link_code,
      m.title,
      m.support_code,
      m.published_at_epic,
      m.created_at_epic
    FROM public.discover_link_metadata m
    WHERE COALESCE(m.published_at_epic, m.created_at_epic) >= (p_week_start::timestamptz)
      AND COALESCE(m.published_at_epic, m.created_at_epic) < ((p_week_end + 1)::timestamptz)
  )
  SELECT
    ri.island_code,
    lm.title,
    COALESCE(lm.support_code, ri.creator_code) AS creator_code,
    lm.published_at_epic,
    lm.created_at_epic,
    ri.week_plays::bigint,
    ri.week_unique::bigint,
    ri.week_peak_ccu_max::bigint
  FROM links_in_window lm
  JOIN public.discover_report_islands ri
    ON ri.island_code = lm.link_code
  WHERE ri.report_id = p_report_id
    AND ri.status = 'reported'
  ORDER BY ri.week_plays DESC NULLS LAST
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
SET statement_timeout = '120s'
AS $$
  WITH links_in_window AS (
    SELECT m.link_code
    FROM public.discover_link_metadata m
    WHERE COALESCE(m.published_at_epic, m.created_at_epic) >= (p_week_start::timestamptz)
      AND COALESCE(m.published_at_epic, m.created_at_epic) < ((p_week_end + 1)::timestamptz)
  )
  SELECT COUNT(*)::bigint
  FROM links_in_window lm
  JOIN public.discover_report_islands ri
    ON ri.island_code = lm.link_code
  WHERE ri.report_id = p_report_id
    AND ri.status = 'reported';
$$;

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
      m.updated_at_epic
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
    NULL::integer AS version
  FROM links_updated lm
  JOIN public.discover_report_islands ri
    ON ri.island_code = lm.link_code
  WHERE ri.report_id = p_report_id
    AND ri.status = 'reported'
  ORDER BY lm.updated_at_epic DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$$;

-- ============================================================
-- 3) Faster KPI finalize: optimize published-count query path
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_kpis(p_report_id uuid, p_prev_report_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_result jsonb;
  v_prev_kpis jsonb;
  v_total_queued int;
  v_suppressed_count int;
  v_new_creators int;
  v_week_start date;
  v_week_end date;
  v_published_count int;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  SELECT COUNT(*)::int INTO v_total_queued
  FROM discover_report_queue WHERE report_id = p_report_id;

  SELECT COUNT(*)::int INTO v_suppressed_count
  FROM discover_report_islands WHERE report_id = p_report_id AND status = 'suppressed';

  WITH creator_first AS (
    SELECT creator_code, MIN(first_seen_at) AS first_seen
    FROM discover_islands_cache
    WHERE creator_code IS NOT NULL
    GROUP BY creator_code
  )
  SELECT COUNT(*)::int INTO v_new_creators
  FROM creator_first
  WHERE first_seen >= v_week_start::timestamptz
    AND first_seen < (v_week_end + 1)::timestamptz;

  WITH ri AS (
    SELECT * FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
  ),
  active AS (
    SELECT * FROM ri WHERE COALESCE(week_unique, 0) >= 5
  ),
  agg AS (
    SELECT
      COUNT(*)::int AS total_reported,
      SUM(week_plays)::bigint AS total_plays,
      SUM(week_unique)::bigint AS total_players,
      SUM(week_minutes)::bigint AS total_minutes,
      SUM(week_favorites)::bigint AS total_favorites,
      SUM(week_recommends)::bigint AS total_recommends,
      COUNT(DISTINCT creator_code) FILTER (WHERE creator_code IS NOT NULL)::int AS total_creators
    FROM ri
  ),
  active_agg AS (
    SELECT
      COUNT(*)::int AS active_count,
      CASE WHEN COUNT(*) > 0 THEN AVG(COALESCE(week_minutes_per_player_avg, 0))::double precision ELSE 0 END AS avg_play_duration,
      CASE WHEN COUNT(*) > 0 THEN AVG(COALESCE(week_peak_ccu_max, 0))::double precision ELSE 0 END AS avg_ccu_per_map,
      CASE WHEN COUNT(*) > 0 THEN AVG(COALESCE(week_d1_avg, 0))::double precision ELSE 0 END AS avg_d1,
      CASE WHEN COUNT(*) > 0 THEN AVG(COALESCE(week_d7_avg, 0))::double precision ELSE 0 END AS avg_d7
    FROM active
  ),
  failed AS (
    SELECT COUNT(*)::int AS cnt FROM ri WHERE COALESCE(week_unique, 0) > 0 AND COALESCE(week_unique, 0) < 500
  ),
  new_maps AS (
    SELECT COUNT(*)::int AS cnt
    FROM discover_report_islands ri2
    JOIN discover_islands_cache c ON c.island_code = ri2.island_code
    WHERE ri2.report_id = p_report_id AND ri2.status = 'reported'
      AND c.first_seen_at >= v_week_start::timestamptz
      AND c.first_seen_at < (v_week_end + 1)::timestamptz
  ),
  revived AS (
    SELECT COUNT(*)::int AS cnt
    FROM discover_report_islands ri3
    JOIN discover_islands_cache c ON c.island_code = ri3.island_code
    WHERE ri3.report_id = p_report_id AND ri3.status = 'reported'
      AND c.reported_streak = 1 AND c.last_suppressed_at IS NOT NULL
  ),
  dead AS (
    SELECT COUNT(*)::int AS cnt
    FROM discover_report_islands ri4
    JOIN discover_islands_cache c ON c.island_code = ri4.island_code
    WHERE ri4.report_id = p_report_id AND ri4.status = 'suppressed'
      AND c.suppressed_streak = 1 AND c.last_reported_at IS NOT NULL
  )
  SELECT jsonb_build_object(
    'totalIslands', COALESCE(v_total_queued, agg.total_reported),
    'activeIslands', aa.active_count,
    'inactiveIslands', COALESCE(v_total_queued, 0) - aa.active_count,
    'suppressedIslands', v_suppressed_count,
    'totalCreators', agg.total_creators,
    'avgMapsPerCreator', CASE WHEN agg.total_creators > 0 THEN ROUND(agg.total_reported::numeric / agg.total_creators, 1) ELSE 0 END,
    'totalPlays', agg.total_plays,
    'totalUniquePlayers', agg.total_players,
    'totalMinutesPlayed', agg.total_minutes,
    'totalFavorites', agg.total_favorites,
    'totalRecommendations', agg.total_recommends,
    'avgPlayDuration', ROUND(aa.avg_play_duration::numeric, 2),
    'avgCCUPerMap', ROUND(aa.avg_ccu_per_map::numeric, 1),
    'avgPlayersPerDay', CASE WHEN agg.total_players > 0 THEN ROUND(agg.total_players::numeric / 7, 0) ELSE 0 END,
    'avgRetentionD1', ROUND(aa.avg_d1::numeric, 4),
    'avgRetentionD7', ROUND(aa.avg_d7::numeric, 4),
    'favToPlayRatio', CASE WHEN agg.total_plays > 0 THEN ROUND(agg.total_favorites::numeric / agg.total_plays, 6) ELSE 0 END,
    'recToPlayRatio', CASE WHEN agg.total_plays > 0 THEN ROUND(agg.total_recommends::numeric / agg.total_plays, 6) ELSE 0 END,
    'newMapsThisWeek', nm.cnt,
    'newCreatorsThisWeek', v_new_creators,
    'failedIslands', f.cnt,
    'baselineAvailable', p_prev_report_id IS NOT NULL,
    'revivedCount', rev.cnt,
    'deadCount', d.cnt
  ) INTO v_result
  FROM agg, active_agg aa, failed f, new_maps nm, revived rev, dead d;

  -- New maps by Epic publish date (optimized by filtering metadata first).
  WITH links_in_window AS (
    SELECT m.link_code
    FROM discover_link_metadata m
    WHERE m.published_at_epic IS NOT NULL
      AND m.published_at_epic >= v_week_start::timestamptz
      AND m.published_at_epic < (v_week_end + 1)::timestamptz
  )
  SELECT COUNT(*)::int INTO v_published_count
  FROM links_in_window lm
  JOIN discover_report_islands ri
    ON ri.island_code = lm.link_code
  WHERE ri.report_id = p_report_id
    AND ri.status = 'reported';

  v_result := v_result || jsonb_build_object('newMapsThisWeekPublished', v_published_count);

  IF p_prev_report_id IS NOT NULL THEN
    SELECT platform_kpis INTO v_prev_kpis FROM discover_reports WHERE id = p_prev_report_id;
    IF v_prev_kpis IS NOT NULL THEN
      v_result := v_result || jsonb_build_object(
        'wowTotalPlays', CASE WHEN (v_prev_kpis->>'totalPlays')::numeric > 0
          THEN ROUND((((v_result->>'totalPlays')::numeric - (v_prev_kpis->>'totalPlays')::numeric) / (v_prev_kpis->>'totalPlays')::numeric) * 100, 1) END,
        'wowTotalPlayers', CASE WHEN (v_prev_kpis->>'totalUniquePlayers')::numeric > 0
          THEN ROUND((((v_result->>'totalUniquePlayers')::numeric - (v_prev_kpis->>'totalUniquePlayers')::numeric) / (v_prev_kpis->>'totalUniquePlayers')::numeric) * 100, 1) END,
        'wowTotalMinutes', CASE WHEN (v_prev_kpis->>'totalMinutesPlayed')::numeric > 0
          THEN ROUND((((v_result->>'totalMinutesPlayed')::numeric - (v_prev_kpis->>'totalMinutesPlayed')::numeric) / (v_prev_kpis->>'totalMinutesPlayed')::numeric) * 100, 1) END,
        'wowActiveIslands', CASE WHEN (v_prev_kpis->>'activeIslands')::numeric > 0
          THEN ROUND((((v_result->>'activeIslands')::numeric - (v_prev_kpis->>'activeIslands')::numeric) / (v_prev_kpis->>'activeIslands')::numeric) * 100, 1) END,
        'wowTotalCreators', CASE WHEN (v_prev_kpis->>'totalCreators')::numeric > 0
          THEN ROUND((((v_result->>'totalCreators')::numeric - (v_prev_kpis->>'totalCreators')::numeric) / (v_prev_kpis->>'totalCreators')::numeric) * 100, 1) END,
        'wowAvgRetentionD1', CASE WHEN (v_prev_kpis->>'avgRetentionD1')::numeric > 0
          THEN ROUND((((v_result->>'avgRetentionD1')::numeric - (v_prev_kpis->>'avgRetentionD1')::numeric) / (v_prev_kpis->>'avgRetentionD1')::numeric) * 100, 1) END,
        'wowAvgRetentionD7', CASE WHEN (v_prev_kpis->>'avgRetentionD7')::numeric > 0
          THEN ROUND((((v_result->>'avgRetentionD7')::numeric - (v_prev_kpis->>'avgRetentionD7')::numeric) / (v_prev_kpis->>'avgRetentionD7')::numeric) * 100, 1) END,
        'wowAvgPlayDuration', CASE WHEN (v_prev_kpis->>'avgPlayDuration')::numeric > 0
          THEN ROUND((((v_result->>'avgPlayDuration')::numeric - (v_prev_kpis->>'avgPlayDuration')::numeric) / (v_prev_kpis->>'avgPlayDuration')::numeric) * 100, 1) END,
        'wowAvgCCUPerMap', CASE WHEN (v_prev_kpis->>'avgCCUPerMap')::numeric > 0
          THEN ROUND((((v_result->>'avgCCUPerMap')::numeric - (v_prev_kpis->>'avgCCUPerMap')::numeric) / (v_prev_kpis->>'avgCCUPerMap')::numeric) * 100, 1) END,
        'wowTotalFavorites', CASE WHEN (v_prev_kpis->>'totalFavorites')::numeric > 0
          THEN ROUND((((v_result->>'totalFavorites')::numeric - (v_prev_kpis->>'totalFavorites')::numeric) / (v_prev_kpis->>'totalFavorites')::numeric) * 100, 1) END,
        'wowTotalRecommendations', CASE WHEN (v_prev_kpis->>'totalRecommendations')::numeric > 0
          THEN ROUND((((v_result->>'totalRecommendations')::numeric - (v_prev_kpis->>'totalRecommendations')::numeric) / (v_prev_kpis->>'totalRecommendations')::numeric) * 100, 1) END,
        'wowNewMaps', (v_result->>'newMapsThisWeek')::int - COALESCE((v_prev_kpis->>'newMapsThisWeek')::int, 0),
        'wowNewCreators', (v_result->>'newCreatorsThisWeek')::int - COALESCE((v_prev_kpis->>'newCreatorsThisWeek')::int, 0),
        'wowRevivedCount', (v_result->>'revivedCount')::int - COALESCE((v_prev_kpis->>'revivedCount')::int, 0),
        'wowDeadCount', (v_result->>'deadCount')::int - COALESCE((v_prev_kpis->>'deadCount')::int, 0),
        'wowFailedIslands', (v_result->>'failedIslands')::int - COALESCE((v_prev_kpis->>'failedIslands')::int, 0),
        'prevTotalPlays', (v_prev_kpis->>'totalPlays')::bigint,
        'prevTotalPlayers', (v_prev_kpis->>'totalUniquePlayers')::bigint,
        'prevTotalMinutes', (v_prev_kpis->>'totalMinutesPlayed')::bigint,
        'prevActiveIslands', (v_prev_kpis->>'activeIslands')::int,
        'prevTotalCreators', (v_prev_kpis->>'totalCreators')::int,
        'prevAvgRetentionD1', (v_prev_kpis->>'avgRetentionD1')::numeric,
        'prevAvgRetentionD7', (v_prev_kpis->>'avgRetentionD7')::numeric,
        'prevAvgPlayDuration', (v_prev_kpis->>'avgPlayDuration')::numeric,
        'prevAvgCCUPerMap', (v_prev_kpis->>'avgCCUPerMap')::numeric,
        'prevNewMapsThisWeek', (v_prev_kpis->>'newMapsThisWeek')::int,
        'prevNewCreatorsThisWeek', (v_prev_kpis->>'newCreatorsThisWeek')::int,
        'prevTotalFavorites', (v_prev_kpis->>'totalFavorites')::bigint,
        'prevTotalRecommendations', (v_prev_kpis->>'totalRecommendations')::bigint,
        'prevRevivedCount', (v_prev_kpis->>'revivedCount')::int,
        'prevDeadCount', (v_prev_kpis->>'deadCount')::int,
        'prevFailedIslands', (v_prev_kpis->>'failedIslands')::int
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$function$;

-- ============================================================
-- 4) Exposure finalize RPCs optimized to restrict to report islands early
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_exposure_analysis(p_report_id uuid, p_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
DECLARE
  result jsonb;
  v_week_start date;
  v_week_end date;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  WITH ri AS (
    SELECT island_code
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
  ),
  base AS (
    SELECT r.*
    FROM discovery_exposure_rollup_daily r
    JOIN ri ON ri.island_code = r.link_code
    WHERE r.date >= v_week_start
      AND r.date <= v_week_end
      AND r.link_code_type = 'island'
      AND r.panel_name NOT LIKE 'Browse%'
  ),
  panel_detail AS (
    SELECT
      b.link_code,
      get_panel_display_name(b.panel_name) AS panel,
      SUM(b.minutes_exposed)::int AS minutes,
      SUM(b.appearances)::int AS appearances,
      MIN(b.best_rank) AS best_rank
    FROM base b
    GROUP BY b.link_code, get_panel_display_name(b.panel_name)
  ),
  panel_breakdown AS (
    SELECT
      pd.link_code,
      jsonb_agg(jsonb_build_object(
        'panel', pd.panel,
        'minutes', pd.minutes,
        'appearances', pd.appearances,
        'best_rank', pd.best_rank
      ) ORDER BY pd.minutes DESC) AS panel_breakdown
    FROM panel_detail pd
    GROUP BY pd.link_code
  ),
  multi_panel AS (
    SELECT
      b.link_code,
      COUNT(DISTINCT b.panel_name)::int AS panels_distinct
    FROM base b
    GROUP BY b.link_code
    HAVING COUNT(DISTINCT b.panel_name) >= 2
    ORDER BY COUNT(DISTINCT b.panel_name) DESC
    LIMIT 10
  ),
  loyalty AS (
    SELECT
      b.link_code,
      b.panel_name,
      SUM(b.minutes_exposed)::int AS total_minutes_in_panel
    FROM base b
    GROUP BY b.link_code, b.panel_name
    ORDER BY SUM(b.minutes_exposed) DESC
    LIMIT 10
  )
  SELECT jsonb_build_object(
    'multiPanelPresence',
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'link_code', mp.link_code,
        'link_code_type', 'island',
        'panels_distinct', mp.panels_distinct,
        'panel_names', (
          SELECT array_agg(DISTINCT get_panel_display_name(b2.panel_name) ORDER BY get_panel_display_name(b2.panel_name))
          FROM base b2
          WHERE b2.link_code = mp.link_code
        ),
        'panel_breakdown', COALESCE(pb.panel_breakdown, '[]'::jsonb),
        'title', COALESCE(dlm.title, dic.title, mp.link_code),
        'creator_code', COALESCE(dlm.support_code, dlm.creator_name, dic.creator_code),
        'image_url', COALESCE(dlm.image_url, dic.image_url)
      ))
      FROM multi_panel mp
      LEFT JOIN panel_breakdown pb ON pb.link_code = mp.link_code
      LEFT JOIN discover_islands_cache dic ON dic.island_code = mp.link_code
      LEFT JOIN discover_link_metadata dlm ON dlm.link_code = mp.link_code
    ), '[]'::jsonb),
    'panelLoyalty',
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'link_code', l.link_code,
        'panel_name', get_panel_display_name(l.panel_name),
        'total_minutes_in_panel', l.total_minutes_in_panel,
        'title', COALESCE(dlm.title, dic.title, l.link_code),
        'creator_code', COALESCE(dlm.support_code, dlm.creator_name, dic.creator_code),
        'image_url', COALESCE(dlm.image_url, dic.image_url)
      ))
      FROM loyalty l
      LEFT JOIN discover_islands_cache dic ON dic.island_code = l.link_code
      LEFT JOIN discover_link_metadata dlm ON dlm.link_code = l.link_code
    ), '[]'::jsonb),
    'versionEnrichment', jsonb_build_object(
      'avgVersion', 0,
      'islandsWithVersion5Plus', 0,
      'totalWithVersion', 0,
      'versionDistribution', '[]'::jsonb
    ),
    'sacCoverage', (
      SELECT jsonb_build_object(
        'totalWithSAC', COUNT(*) FILTER (WHERE dlm.support_code IS NOT NULL AND dlm.support_code <> '')::int,
        'totalChecked', COUNT(*)::int,
        'sacPct', CASE WHEN COUNT(*) > 0
          THEN (COUNT(*) FILTER (WHERE dlm.support_code IS NOT NULL AND dlm.support_code <> '')::numeric / COUNT(*)::numeric * 100)::numeric(5,1)
          ELSE 0 END
      )
      FROM discover_report_islands ri
      JOIN discover_link_metadata dlm ON dlm.link_code = ri.island_code
      WHERE ri.report_id = p_report_id
        AND ri.status = 'reported'
    )
  ) INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_finalize_exposure_efficiency(p_report_id uuid, p_limit integer DEFAULT 15)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
DECLARE
  v_week_start date;
  v_week_end date;
  v_result jsonb;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  IF v_week_start IS NULL THEN
    RETURN jsonb_build_object('topExposureEfficiency', '[]'::jsonb, 'worstExposureEfficiency', '[]'::jsonb);
  END IF;

  WITH ri AS (
    SELECT island_code, title, creator_code, category, week_plays, week_unique
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
  ),
  base AS (
    SELECT r.*
    FROM discovery_exposure_rollup_daily r
    JOIN ri ON ri.island_code = r.link_code
    WHERE r.date >= v_week_start
      AND r.date <= v_week_end
      AND r.link_code_type = 'island'
      AND r.panel_name NOT LIKE 'Browse%'
  ),
  exposure_agg AS (
    SELECT
      b.link_code,
      SUM(b.minutes_exposed)::numeric AS total_minutes_exposed,
      COUNT(DISTINCT b.panel_name)::int AS distinct_panels,
      MIN(b.best_rank) AS best_rank
    FROM base b
    GROUP BY b.link_code
    HAVING SUM(b.minutes_exposed) > 5
  ),
  panel_detail AS (
    SELECT
      b.link_code,
      get_panel_display_name(b.panel_name) AS panel_name,
      SUM(b.minutes_exposed)::int AS minutes,
      SUM(b.appearances)::int AS appearances,
      MIN(b.best_rank) AS best_rank
    FROM base b
    GROUP BY b.link_code, get_panel_display_name(b.panel_name)
  ),
  panel_breakdown_json AS (
    SELECT
      link_code,
      jsonb_agg(jsonb_build_object(
        'panel', panel_name,
        'minutes', minutes,
        'appearances', appearances,
        'best_rank', best_rank
      ) ORDER BY minutes DESC) AS panel_breakdown
    FROM panel_detail
    GROUP BY link_code
  ),
  joined AS (
    SELECT
      e.link_code AS island_code,
      COALESCE(dlm.title, ri.title, e.link_code) AS title,
      COALESCE(dlm.support_code, dlm.creator_name, ri.creator_code) AS creator_code,
      ri.category,
      ri.week_plays,
      ri.week_unique,
      e.total_minutes_exposed,
      e.distinct_panels,
      e.best_rank,
      CASE WHEN e.total_minutes_exposed > 0
        THEN ri.week_plays::numeric / e.total_minutes_exposed
        ELSE 0
      END AS plays_per_min_exposed,
      CASE WHEN e.total_minutes_exposed > 0
        THEN ri.week_unique::numeric / e.total_minutes_exposed
        ELSE 0
      END AS players_per_min_exposed,
      COALESCE(dlm.image_url, dic.image_url) AS image_url,
      pb.panel_breakdown
    FROM exposure_agg e
    JOIN ri ON ri.island_code = e.link_code
    LEFT JOIN discover_islands_cache dic ON dic.island_code = e.link_code
    LEFT JOIN discover_link_metadata dlm ON dlm.link_code = e.link_code
    LEFT JOIN panel_breakdown_json pb ON pb.link_code = e.link_code
    WHERE ri.week_plays IS NOT NULL AND ri.week_plays > 0
  )
  SELECT jsonb_build_object(
    'topExposureEfficiency',
    COALESCE((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY t.plays_per_min_exposed DESC)
      FROM (
        SELECT island_code, title, creator_code, category, week_plays, week_unique,
               ROUND(total_minutes_exposed::numeric, 1) AS total_minutes_exposed,
               distinct_panels, best_rank,
               ROUND(plays_per_min_exposed::numeric, 2) AS plays_per_min_exposed,
               ROUND(players_per_min_exposed::numeric, 2) AS players_per_min_exposed,
               image_url, panel_breakdown
        FROM joined
        ORDER BY plays_per_min_exposed DESC
        LIMIT p_limit
      ) t
    ), '[]'::jsonb),
    'worstExposureEfficiency',
    COALESCE((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY t.plays_per_min_exposed ASC)
      FROM (
        SELECT island_code, title, creator_code, category, week_plays, week_unique,
               ROUND(total_minutes_exposed::numeric, 1) AS total_minutes_exposed,
               distinct_panels, best_rank,
               ROUND(plays_per_min_exposed::numeric, 2) AS plays_per_min_exposed,
               ROUND(players_per_min_exposed::numeric, 2) AS players_per_min_exposed,
               image_url, panel_breakdown
        FROM joined
        WHERE total_minutes_exposed >= 30
        ORDER BY plays_per_min_exposed ASC
        LIMIT p_limit
      ) t
    ), '[]'::jsonb),
    'exposureEfficiencyStats',
    COALESCE((
      SELECT row_to_json(s)::jsonb FROM (
        SELECT
          COUNT(*) AS total_islands_with_exposure,
          ROUND(AVG(plays_per_min_exposed)::numeric, 2) AS avg_plays_per_min,
          ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY plays_per_min_exposed)::numeric, 2) AS median_plays_per_min,
          ROUND(AVG(total_minutes_exposed)::numeric, 1) AS avg_minutes_exposed
        FROM joined
      ) s
    ), '{}'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;
