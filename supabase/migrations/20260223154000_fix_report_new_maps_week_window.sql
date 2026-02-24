-- Fix weekly window semantics for "new maps" and "new creators" in report KPIs.
-- Keep two explicit metrics:
-- - newMapsThisWeek: first seen in our cache during the report week
-- - newMapsThisWeekPublished: Epic published_at during the report week

CREATE OR REPLACE FUNCTION public.report_finalize_kpis(p_report_id uuid, p_prev_report_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '45s'
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

  -- New maps by Epic publish date (preferred "published this week" signal)
  SELECT COUNT(*)::int INTO v_published_count
  FROM discover_report_islands ri
  JOIN discover_link_metadata lm ON lm.link_code = ri.island_code
  WHERE ri.report_id = p_report_id AND ri.status = 'reported'
    AND lm.published_at_epic IS NOT NULL
    AND lm.published_at_epic >= v_week_start::timestamptz
    AND lm.published_at_epic < (v_week_end + 1)::timestamptz;
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

