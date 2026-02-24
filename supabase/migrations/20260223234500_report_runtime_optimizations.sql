-- Runtime optimizations for report rebuild and exposure injection.
-- Keep full report data; reduce heavy scans and contention.

CREATE INDEX IF NOT EXISTS discover_report_islands_report_status_creator_idx
  ON public.discover_report_islands (report_id, status, creator_code);

CREATE INDEX IF NOT EXISTS discovery_exposure_rollup_daily_top_panel_idx
  ON public.discovery_exposure_rollup_daily (date, target_id, panel_name, link_code)
  INCLUDE (surface_name, link_code_type, minutes_exposed, ccu_max_seen, best_rank, avg_rank);

CREATE OR REPLACE FUNCTION public.discovery_exposure_top_by_panel(
  p_date_from DATE, p_date_to DATE, p_limit_per_panel INT DEFAULT 3
)
RETURNS TABLE (
  target_id UUID, surface_name TEXT, panel_name TEXT, link_code TEXT, link_code_type TEXT,
  minutes_exposed INT, ccu_max_seen INT, best_rank INT, avg_rank DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH active_targets AS (
    SELECT id
    FROM public.discovery_exposure_targets
    WHERE last_ok_tick_at IS NOT NULL
  ),
  base AS (
    SELECT
      r.target_id,
      MAX(r.surface_name) AS surface_name,
      r.panel_name,
      r.link_code,
      MAX(r.link_code_type) AS link_code_type,
      SUM(r.minutes_exposed)::int AS minutes_exposed,
      MAX(r.ccu_max_seen)::int AS ccu_max_seen,
      MIN(r.best_rank)::int AS best_rank,
      (SUM(r.avg_rank * r.minutes_exposed) / NULLIF(SUM(r.minutes_exposed), 0))::double precision AS avg_rank
    FROM public.discovery_exposure_rollup_daily r
    JOIN active_targets t ON t.id = r.target_id
    WHERE r.date >= p_date_from
      AND r.date <= p_date_to
    GROUP BY r.target_id, r.panel_name, r.link_code
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY target_id, panel_name
        ORDER BY minutes_exposed DESC, ccu_max_seen DESC NULLS LAST, link_code ASC
      ) AS rn
    FROM base
  )
  SELECT
    target_id, surface_name, panel_name, link_code, link_code_type,
    minutes_exposed, ccu_max_seen, best_rank, avg_rank
  FROM ranked
  WHERE rn <= GREATEST(p_limit_per_panel, 1)
  ORDER BY target_id, panel_name, rn;
$$;

CREATE OR REPLACE FUNCTION public.discovery_exposure_panel_daily_summaries(
  p_date_from DATE, p_date_to DATE
)
RETURNS TABLE (
  date DATE, target_id UUID, surface_name TEXT, panel_name TEXT,
  maps INT, creators INT, collections INT
)
LANGUAGE sql
STABLE
SET search_path = public
SET statement_timeout = '120s'
AS $$
  WITH active_targets AS (
    SELECT id
    FROM public.discovery_exposure_targets
    WHERE last_ok_tick_at IS NOT NULL
  ),
  base AS (
    SELECT r.date, r.target_id, r.surface_name, r.panel_name, r.link_code, r.link_code_type
    FROM public.discovery_exposure_rollup_daily r
    JOIN active_targets t ON t.id = r.target_id
    WHERE r.date >= p_date_from
      AND r.date <= p_date_to
  ),
  islands AS (
    SELECT b.date, b.target_id, b.surface_name, b.panel_name, b.link_code
    FROM base b
    WHERE b.link_code_type = 'island'
  ),
  coll AS (
    SELECT b.date, b.target_id, b.surface_name, b.panel_name, b.link_code
    FROM base b
    WHERE b.link_code_type = 'collection'
  ),
  creators AS (
    SELECT DISTINCT i.date, i.target_id, i.surface_name, i.panel_name, m.support_code AS creator_code
    FROM islands i
    JOIN public.discover_link_metadata m ON m.link_code = i.link_code
    WHERE m.support_code IS NOT NULL
      AND m.support_code <> ''
  )
  SELECT
    t.date, t.target_id, t.surface_name, t.panel_name,
    COALESCE(m.maps, 0)::int AS maps,
    COALESCE(cr.creators, 0)::int AS creators,
    COALESCE(col.collections, 0)::int AS collections
  FROM (SELECT DISTINCT b.date, b.target_id, b.surface_name, b.panel_name FROM base b) t
  LEFT JOIN (
    SELECT i2.date, i2.target_id, i2.surface_name, i2.panel_name, COUNT(DISTINCT i2.link_code)::int AS maps
    FROM islands i2
    GROUP BY i2.date, i2.target_id, i2.surface_name, i2.panel_name
  ) m ON m.date = t.date AND m.target_id = t.target_id AND m.surface_name = t.surface_name AND m.panel_name = t.panel_name
  LEFT JOIN (
    SELECT cr2.date, cr2.target_id, cr2.surface_name, cr2.panel_name, COUNT(DISTINCT cr2.creator_code)::int AS creators
    FROM creators cr2
    GROUP BY cr2.date, cr2.target_id, cr2.surface_name, cr2.panel_name
  ) cr ON cr.date = t.date AND cr.target_id = t.target_id AND cr.surface_name = t.surface_name AND cr.panel_name = t.panel_name
  LEFT JOIN (
    SELECT col2.date, col2.target_id, col2.surface_name, col2.panel_name, COUNT(DISTINCT col2.link_code)::int AS collections
    FROM coll col2
    GROUP BY col2.date, col2.target_id, col2.surface_name, col2.panel_name
  ) col ON col.date = t.date AND col.target_id = t.target_id AND col.surface_name = t.surface_name AND col.panel_name = t.panel_name
  ORDER BY t.date DESC, t.target_id, t.panel_name;
$$;

CREATE OR REPLACE FUNCTION public.report_finalize_kpis(p_report_id uuid, p_prev_report_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
DECLARE
  v_result jsonb;
  v_prev_kpis jsonb;
  v_total_queued int;
  v_suppressed_count int;
  v_new_creators int := 0;
  v_week_start date;
  v_week_end date;
  v_published_count int := 0;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports
  WHERE id = p_report_id;

  SELECT COUNT(*)::int INTO v_total_queued
  FROM discover_report_queue
  WHERE report_id = p_report_id;

  SELECT COUNT(*)::int INTO v_suppressed_count
  FROM discover_report_islands
  WHERE report_id = p_report_id
    AND status = 'suppressed';

  SELECT COALESCE(public.report_new_islands_by_launch_count(p_report_id, v_week_start, v_week_end), 0)::int
    INTO v_published_count;

  WITH report_creators AS (
    SELECT DISTINCT COALESCE(ri.creator_code, '') AS creator_code
    FROM discover_report_islands ri
    WHERE ri.report_id = p_report_id
      AND ri.status = 'reported'
      AND ri.creator_code IS NOT NULL
      AND ri.creator_code <> ''
  ),
  creator_first AS (
    SELECT
      m.support_code AS creator_code,
      MIN(COALESCE(m.published_at_epic, m.created_at_epic)) AS first_seen
    FROM discover_link_metadata m
    JOIN report_creators rc ON rc.creator_code = m.support_code
    WHERE m.support_code IS NOT NULL
      AND m.support_code <> ''
      AND COALESCE(m.published_at_epic, m.created_at_epic) IS NOT NULL
    GROUP BY m.support_code
  )
  SELECT COUNT(*)::int INTO v_new_creators
  FROM creator_first
  WHERE first_seen >= v_week_start::timestamptz
    AND first_seen < (v_week_end + 1)::timestamptz;

  WITH ri AS (
    SELECT *
    FROM discover_report_islands
    WHERE report_id = p_report_id
      AND status = 'reported'
  ),
  active AS (
    SELECT *
    FROM ri
    WHERE COALESCE(week_unique, 0) >= 5
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
    SELECT COUNT(*)::int AS cnt
    FROM ri
    WHERE COALESCE(week_unique, 0) > 0
      AND COALESCE(week_unique, 0) < 500
  ),
  revived AS (
    SELECT COUNT(*)::int AS cnt
    FROM discover_report_islands ri3
    JOIN discover_islands_cache c ON c.island_code = ri3.island_code
    WHERE ri3.report_id = p_report_id
      AND ri3.status = 'reported'
      AND c.reported_streak = 1
      AND c.last_suppressed_at IS NOT NULL
  ),
  dead AS (
    SELECT COUNT(*)::int AS cnt
    FROM discover_report_islands ri4
    JOIN discover_islands_cache c ON c.island_code = ri4.island_code
    WHERE ri4.report_id = p_report_id
      AND ri4.status = 'suppressed'
      AND c.suppressed_streak = 1
      AND c.last_reported_at IS NOT NULL
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
    'newMapsThisWeek', v_published_count,
    'newMapsThisWeekPublished', v_published_count,
    'newCreatorsThisWeek', v_new_creators,
    'failedIslands', f.cnt,
    'baselineAvailable', p_prev_report_id IS NOT NULL,
    'revivedCount', rev.cnt,
    'deadCount', d.cnt
  ) INTO v_result
  FROM agg, active_agg aa, failed f, revived rev, dead d;

  IF p_prev_report_id IS NOT NULL THEN
    SELECT platform_kpis INTO v_prev_kpis
    FROM discover_reports
    WHERE id = p_prev_report_id;

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
        'wowFailedIslands', (v_result->>'failedIslands')::int - COALESCE((v_prev_kpis->>'failedIslands')::int, 0)
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$$;
