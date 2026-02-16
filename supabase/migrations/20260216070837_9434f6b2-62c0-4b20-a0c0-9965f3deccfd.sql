
-- ============================================================
-- RPC 1: report_finalize_kpis
-- Computes all platform KPIs + WoW deltas directly in SQL
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_kpis(
  p_report_id uuid,
  p_prev_report_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
DECLARE
  v_result jsonb;
  v_prev_kpis jsonb;
  v_total_queued int;
  v_suppressed_count int;
  v_new_creators int;
  v_week_start date;
  v_week_end date;
BEGIN
  -- Get report dates
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  -- Queue total
  SELECT COUNT(*)::int INTO v_total_queued
  FROM discover_report_queue WHERE report_id = p_report_id;

  -- Suppressed count
  SELECT COUNT(*)::int INTO v_suppressed_count
  FROM discover_report_islands WHERE report_id = p_report_id AND status = 'suppressed';

  -- New creators this week (from cache)
  WITH creator_first AS (
    SELECT creator_code, MIN(first_seen_at) AS first_seen
    FROM discover_islands_cache
    WHERE creator_code IS NOT NULL
    GROUP BY creator_code
  )
  SELECT COUNT(*)::int INTO v_new_creators
  FROM creator_first WHERE first_seen >= v_week_start::timestamptz;

  -- Main KPIs from reported islands
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

  -- Also get newMapsThisWeekPublished from metadata
  DECLARE
    v_published_count int;
  BEGIN
    SELECT COUNT(*)::int INTO v_published_count
    FROM discover_report_islands ri
    JOIN discover_link_metadata lm ON lm.link_code = ri.island_code
    WHERE ri.report_id = p_report_id AND ri.status = 'reported'
      AND lm.published_at_epic IS NOT NULL
      AND lm.published_at_epic >= v_week_start::timestamptz
      AND lm.published_at_epic < (v_week_end + 1)::timestamptz;
    v_result := v_result || jsonb_build_object('newMapsThisWeekPublished', v_published_count);
  END;

  -- WoW deltas
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
          THEN ROUND((((v_result->>'activeIslands')::numeric - (v_prev_kpis->>'activeIslands')::numeric) / (v_prev_kpis->>'activeIslands')::numeric) * 100, 1) END
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$fn$;


-- ============================================================
-- RPC 2: report_finalize_rankings
-- Computes ALL top-N ranking lists directly in SQL
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_rankings(
  p_report_id uuid,
  p_limit int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
DECLARE
  v_result jsonb := '{}'::jsonb;
BEGIN
  -- Helper: build ranking item JSON
  -- We'll use CTEs for each ranking

  -- topPeakCCU (all)
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_peak_ccu_max AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_peak_ccu_max, 0) > 0
    ORDER BY week_peak_ccu_max DESC NULLS LAST LIMIT p_limit
  )
  SELECT jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code), 'title', title,
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', val, 'subtitle', creator_code
  )) INTO v_result FROM ranked;
  v_result := jsonb_build_object('topPeakCCU', COALESCE(v_result, '[]'::jsonb));

  -- topPeakCCU_UGC
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_peak_ccu_max AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_peak_ccu_max, 0) > 0
      AND creator_code NOT IN ('fortnite', 'epic')
    ORDER BY week_peak_ccu_max DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topPeakCCU_UGC', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code), 'title', title,
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', val, 'subtitle', creator_code
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topUniquePlayers
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_unique AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_unique, 0) > 0
    ORDER BY week_unique DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topUniquePlayers', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topTotalPlays
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_plays AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_plays, 0) > 0
    ORDER BY week_plays DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topTotalPlays', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topMinutesPlayed
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_minutes AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_minutes, 0) > 0
    ORDER BY week_minutes DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topMinutesPlayed', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topAvgMinutesPerPlayer (filter: >= 1000 plays AND >= 500 unique)
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, 
           ROUND(week_minutes_per_player_avg::numeric, 1) AS val, week_plays
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000 AND COALESCE(week_unique, 0) >= 500
      AND COALESCE(week_minutes_per_player_avg, 0) > 0
    ORDER BY week_minutes_per_player_avg DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topAvgMinutesPerPlayer', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val,
    'subtitle', week_plays || ' plays'
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topRetentionD1 (filter: >= 50 unique)
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, ROUND(week_d1_avg::numeric, 4) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_unique, 0) >= 50 AND COALESCE(week_d1_avg, 0) > 0
    ORDER BY week_d1_avg DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRetentionD1', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topRetentionD7
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, ROUND(week_d7_avg::numeric, 4) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_unique, 0) >= 50 AND COALESCE(week_d7_avg, 0) > 0
    ORDER BY week_d7_avg DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRetentionD7', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topFavorites
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_favorites AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_favorites, 0) > 0
    ORDER BY week_favorites DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topFavorites', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- topRecommendations
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_recommends AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported' AND COALESCE(week_recommends, 0) > 0
    ORDER BY week_recommends DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRecommendations', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- Derived metrics rankings (stickiness, efficiency, etc.)
  -- topStickinessD1: plays * mpp * d1
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           COALESCE(week_plays,0) * COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d1_avg,0) AS stickiness
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays,0) > 0 AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d1_avg,0) > 0
    ORDER BY stickiness DESC LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topStickinessD1', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', ROUND(stickiness::numeric, 0)
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topStickinessD7
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           COALESCE(week_plays,0) * COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d7_avg,0) AS stickiness
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays,0) > 0 AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d7_avg,0) > 0
    ORDER BY stickiness DESC LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topStickinessD7', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', ROUND(stickiness::numeric, 0)
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topStickinessD1_UGC
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           COALESCE(week_plays,0) * COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d1_avg,0) AS stickiness
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND creator_code NOT IN ('fortnite', 'epic')
      AND COALESCE(week_plays,0) > 0 AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d1_avg,0) > 0
    ORDER BY stickiness DESC LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topStickinessD1_UGC', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', ROUND(stickiness::numeric, 0)
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topStickinessD7_UGC
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           COALESCE(week_plays,0) * COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d7_avg,0) AS stickiness
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND creator_code NOT IN ('fortnite', 'epic')
      AND COALESCE(week_plays,0) > 0 AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d7_avg,0) > 0
    ORDER BY stickiness DESC LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topStickinessD7_UGC', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', ROUND(stickiness::numeric, 0)
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topPlaysPerPlayer (filter: >= 1000 plays)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((week_plays::numeric / NULLIF(week_unique, 0)), 2) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000 AND COALESCE(week_unique, 0) > 0
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topPlaysPerPlayer', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topFavsPer100 (filter: >= 100 unique, >= 10 favs)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((week_favorites::numeric / NULLIF(week_unique, 0)) * 100, 1) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_unique, 0) >= 100 AND COALESCE(week_favorites, 0) >= 10
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topFavsPer100', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topRecPer100 (filter: >= 100 unique, >= 25 recs)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((week_recommends::numeric / NULLIF(week_unique, 0)) * 100, 1) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_unique, 0) >= 100 AND COALESCE(week_recommends, 0) >= 25
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRecPer100', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topFavsPerPlay (filter: >= 1000 plays)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((week_favorites::numeric / NULLIF(week_plays, 0)), 4) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topFavsPerPlay', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topRecsPerPlay (filter: >= 1000 plays)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((week_recommends::numeric / NULLIF(week_plays, 0)), 4) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRecsPerPlay', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topRetentionAdjD1 (mpp * d1, filter: >= 1000 plays, >= 500 unique)
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d1_avg,0))::numeric, 1) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000 AND COALESCE(week_unique, 0) >= 500
      AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d1_avg,0) > 0
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRetentionAdjD1', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- topRetentionAdjD7
  WITH enriched AS (
    SELECT island_code, title, creator_code, category,
           ROUND((COALESCE(week_minutes_per_player_avg,0) * COALESCE(week_d7_avg,0))::numeric, 1) AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_plays, 0) >= 1000 AND COALESCE(week_unique, 0) >= 500
      AND COALESCE(week_minutes_per_player_avg,0) > 0 AND COALESCE(week_d7_avg,0) > 0
    ORDER BY val DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('topRetentionAdjD7', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM enriched;

  -- failedIslandsList (lowest unique players, < 500 unique)
  WITH ranked AS (
    SELECT island_code, title, creator_code, category, week_unique AS val
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND COALESCE(week_unique, 0) > 0 AND COALESCE(week_unique, 0) < 500
    ORDER BY week_unique ASC LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('failedIslandsList', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
    'value', val, 'label', val || ' players'
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- Revived islands (reported_streak=1 + had suppressed before)
  WITH ranked AS (
    SELECT ri.island_code, ri.title, ri.creator_code, ri.category, ri.week_plays AS val
    FROM discover_report_islands ri
    JOIN discover_islands_cache c ON c.island_code = ri.island_code
    WHERE ri.report_id = p_report_id AND ri.status = 'reported'
      AND c.reported_streak = 1 AND c.last_suppressed_at IS NOT NULL
    ORDER BY ri.week_plays DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('revivedIslands', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', val
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  -- Dead islands (newly suppressed, were reported before)
  WITH ranked AS (
    SELECT ri.island_code, ri.title, ri.creator_code, ri.category, c.last_week_plays AS val
    FROM discover_report_islands ri
    JOIN discover_islands_cache c ON c.island_code = ri.island_code
    WHERE ri.report_id = p_report_id AND ri.status = 'suppressed'
      AND c.suppressed_streak = 1 AND c.last_reported_at IS NOT NULL
    ORDER BY c.last_week_plays DESC NULLS LAST LIMIT p_limit
  )
  SELECT v_result || jsonb_build_object('deadIslands', COALESCE(jsonb_agg(jsonb_build_object(
    'code', island_code, 'name', COALESCE(title, island_code),
    'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'), 'value', COALESCE(val, 0)
  )), '[]'::jsonb)) INTO v_result FROM ranked;

  RETURN v_result;
END;
$fn$;


-- ============================================================
-- RPC 3: report_finalize_creators
-- Creator aggregation rankings
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_creators(
  p_report_id uuid,
  p_limit int DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
  WITH agg AS (
    SELECT
      COALESCE(creator_code, 'unknown') AS creator,
      SUM(COALESCE(week_plays, 0))::bigint AS total_plays,
      SUM(COALESCE(week_unique, 0))::bigint AS unique_players,
      SUM(COALESCE(week_minutes, 0))::bigint AS minutes_played,
      MAX(COALESCE(week_peak_ccu_max, 0))::int AS peak_ccu,
      SUM(COALESCE(week_favorites, 0))::bigint AS favorites,
      SUM(COALESCE(week_recommends, 0))::bigint AS recommendations,
      COUNT(*)::int AS maps
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
    GROUP BY COALESCE(creator_code, 'unknown')
  )
  SELECT jsonb_build_object(
    'topCreatorsByPlays', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', creator, 'creator', creator, 'value', total_plays)), '[]') FROM (SELECT * FROM agg ORDER BY total_plays DESC LIMIT p_limit) t),
    'topCreatorsByPlayers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', creator, 'creator', creator, 'value', unique_players)), '[]') FROM (SELECT * FROM agg ORDER BY unique_players DESC LIMIT p_limit) t),
    'topCreatorsByMinutes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', creator, 'creator', creator, 'value', minutes_played)), '[]') FROM (SELECT * FROM agg ORDER BY minutes_played DESC LIMIT p_limit) t),
    'topCreatorsByCCU', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', creator, 'creator', creator, 'value', peak_ccu)), '[]') FROM (SELECT * FROM agg ORDER BY peak_ccu DESC LIMIT p_limit) t)
  );
$fn$;


-- ============================================================
-- RPC 4: report_finalize_categories
-- Category aggregation + popularity + top tags
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_categories(
  p_report_id uuid,
  p_limit int DEFAULT 15
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
  WITH cat_agg AS (
    SELECT
      COALESCE(NULLIF(category, 'None'), 'Fortnite UGC') AS cat_name,
      SUM(COALESCE(week_plays, 0))::bigint AS total_plays,
      SUM(COALESCE(week_unique, 0))::bigint AS unique_players,
      SUM(COALESCE(week_minutes, 0))::bigint AS minutes_played,
      MAX(COALESCE(week_peak_ccu_max, 0))::int AS peak_ccu,
      COUNT(*)::int AS maps
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
    GROUP BY COALESCE(NULLIF(category, 'None'), 'Fortnite UGC')
  ),
  tag_agg AS (
    SELECT tag, COUNT(*)::int AS cnt
    FROM discover_report_islands,
         LATERAL jsonb_array_elements_text(COALESCE(tags, '[]'::jsonb)) AS tag
    WHERE report_id = p_report_id AND status = 'reported'
    GROUP BY tag
    ORDER BY cnt DESC
    LIMIT 20
  )
  SELECT jsonb_build_object(
    'categoryShare', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'name', cat_name, 'title', cat_name, 'category', cat_name,
      'totalPlays', total_plays, 'uniquePlayers', unique_players, 'maps', maps,
      'value', total_plays
    ) ORDER BY total_plays DESC), '[]') FROM cat_agg LIMIT p_limit),
    'categoryPopularity', (SELECT COALESCE(jsonb_object_agg(cat_name, maps), '{}') FROM (SELECT * FROM cat_agg ORDER BY maps DESC LIMIT 10) t),
    'topCategoriesByPlays', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', cat_name, 'value', total_plays) ORDER BY total_plays DESC), '[]') FROM cat_agg LIMIT p_limit),
    'topTags', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', tag, 'tag', tag, 'value', cnt, 'count', cnt)), '[]') FROM tag_agg)
  );
$fn$;


-- ============================================================
-- RPC 5: report_finalize_distributions
-- Retention distributions + low perf histogram
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_distributions(p_report_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '30s'
AS $fn$
  WITH ri AS (
    SELECT week_d1_avg, week_d7_avg, week_unique
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
  ),
  d1_dist AS (
    SELECT jsonb_agg(jsonb_build_object('range', range, 'count', cnt) ORDER BY ord) AS dist FROM (
      SELECT 1 AS ord, '0-5%' AS range, COUNT(*) FILTER (WHERE week_d1_avg >= 0 AND week_d1_avg < 0.05) AS cnt FROM ri UNION ALL
      SELECT 2, '5-10%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.05 AND week_d1_avg < 0.10) FROM ri UNION ALL
      SELECT 3, '10-20%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.10 AND week_d1_avg < 0.20) FROM ri UNION ALL
      SELECT 4, '20-30%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.20 AND week_d1_avg < 0.30) FROM ri UNION ALL
      SELECT 5, '30-40%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.30 AND week_d1_avg < 0.40) FROM ri UNION ALL
      SELECT 6, '40-50%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.40 AND week_d1_avg < 0.50) FROM ri UNION ALL
      SELECT 7, '50-60%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.50 AND week_d1_avg < 0.60) FROM ri UNION ALL
      SELECT 8, '60-70%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.60 AND week_d1_avg < 0.70) FROM ri UNION ALL
      SELECT 9, '70-80%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.70 AND week_d1_avg < 0.80) FROM ri UNION ALL
      SELECT 10, '80-90%', COUNT(*) FILTER (WHERE week_d1_avg >= 0.80 AND week_d1_avg < 0.90) FROM ri UNION ALL
      SELECT 11, '90%+', COUNT(*) FILTER (WHERE week_d1_avg >= 0.90) FROM ri
    ) t
  ),
  d7_dist AS (
    SELECT jsonb_agg(jsonb_build_object('range', range, 'count', cnt) ORDER BY ord) AS dist FROM (
      SELECT 1 AS ord, '0-5%' AS range, COUNT(*) FILTER (WHERE week_d7_avg >= 0 AND week_d7_avg < 0.05) AS cnt FROM ri UNION ALL
      SELECT 2, '5-10%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.05 AND week_d7_avg < 0.10) FROM ri UNION ALL
      SELECT 3, '10-20%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.10 AND week_d7_avg < 0.20) FROM ri UNION ALL
      SELECT 4, '20-30%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.20 AND week_d7_avg < 0.30) FROM ri UNION ALL
      SELECT 5, '30-40%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.30 AND week_d7_avg < 0.40) FROM ri UNION ALL
      SELECT 6, '40-50%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.40 AND week_d7_avg < 0.50) FROM ri UNION ALL
      SELECT 7, '50-60%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.50 AND week_d7_avg < 0.60) FROM ri UNION ALL
      SELECT 8, '60-70%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.60 AND week_d7_avg < 0.70) FROM ri UNION ALL
      SELECT 9, '70-80%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.70 AND week_d7_avg < 0.80) FROM ri UNION ALL
      SELECT 10, '80-90%', COUNT(*) FILTER (WHERE week_d7_avg >= 0.80 AND week_d7_avg < 0.90) FROM ri UNION ALL
      SELECT 11, '90%+', COUNT(*) FILTER (WHERE week_d7_avg >= 0.90) FROM ri
    ) t
  ),
  low_perf AS (
    SELECT jsonb_agg(jsonb_build_object('range', range, 'count', cnt) ORDER BY ord) AS dist FROM (
      SELECT 1 AS ord, '<50' AS range, COUNT(*) FILTER (WHERE COALESCE(week_unique,0) < 50 AND COALESCE(week_unique,0) > 0) AS cnt FROM ri UNION ALL
      SELECT 2, '<100', COUNT(*) FILTER (WHERE COALESCE(week_unique,0) >= 50 AND COALESCE(week_unique,0) < 100) FROM ri UNION ALL
      SELECT 3, '<500', COUNT(*) FILTER (WHERE COALESCE(week_unique,0) >= 100 AND COALESCE(week_unique,0) < 500) FROM ri
    ) t
  )
  SELECT jsonb_build_object(
    'retentionDistributionD1', COALESCE(d1.dist, '[]'),
    'retentionDistributionD7', COALESCE(d7.dist, '[]'),
    'lowPerfHistogram', COALESCE(lp.dist, '[]')
  )
  FROM d1_dist d1, d7_dist d7, low_perf lp;
$fn$;


-- ============================================================
-- RPC 6: report_finalize_trending
-- NLP N-gram trending topics computed in SQL
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_trending(
  p_report_id uuid,
  p_min_islands int DEFAULT 5,
  p_limit int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
DECLARE
  v_stopwords text[] := ARRAY[
    'the','a','an','and','or','of','in','on','at','to','for','is','it',
    'by','with','from','up','out','if','my','no','not','but','all','new',
    'your','you','me','we','us','so','do','be','am','are','was','get',
    'has','had','how','its','let','may','our','own','say','she','too',
    'use','way','who','did','got','old','see','now','man','day',
    'any','few','big','per','try','ask',
    'fortnite','map','island','game','mode','v2','v3','v4',
    'chapter','season','update','beta','alpha','test','pro','mega','ultra',
    'super','extreme','ultimate','best','top','epic','updated'
  ];
  v_result jsonb;
BEGIN
  WITH ri AS (
    SELECT island_code, title, week_plays, week_unique, week_peak_ccu_max, week_d1_avg
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND title IS NOT NULL AND title <> ''
  ),
  -- Clean titles and extract words
  cleaned AS (
    SELECT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           regexp_split_to_array(
             lower(regexp_replace(regexp_replace(title, '[^a-zA-Z0-9\s-]', ' ', 'g'), '\s+', ' ', 'g')),
             '\s+'
           ) AS words
    FROM ri
  ),
  -- Extract 1-grams (words with length >= 3)
  unigrams AS (
    SELECT DISTINCT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           word AS ngram
    FROM cleaned,
         LATERAL unnest(words) AS word
    WHERE length(word) >= 3 AND word <> ALL(v_stopwords)
  ),
  -- Extract 2-grams
  bigrams AS (
    SELECT DISTINCT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           words[i] || ' ' || words[i+1] AS ngram
    FROM cleaned,
         LATERAL generate_series(1, array_length(words, 1) - 1) AS i
    WHERE length(words[i]) >= 2 AND length(words[i+1]) >= 2
      AND words[i] <> ALL(v_stopwords) AND words[i+1] <> ALL(v_stopwords)
  ),
  -- Combine and aggregate
  all_ngrams AS (
    SELECT ngram, island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg FROM unigrams
    UNION ALL
    SELECT ngram, island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg FROM bigrams
  ),
  agg AS (
    SELECT
      ngram,
      COUNT(DISTINCT island_code)::int AS islands,
      SUM(COALESCE(week_plays, 0))::bigint AS total_plays,
      SUM(COALESCE(week_unique, 0))::bigint AS total_players,
      MAX(COALESCE(week_peak_ccu_max, 0))::int AS peak_ccu,
      AVG(COALESCE(week_d1_avg, 0)) FILTER (WHERE COALESCE(week_d1_avg, 0) > 0) AS avg_d1
    FROM all_ngrams
    GROUP BY ngram
    HAVING COUNT(DISTINCT island_code) >= p_min_islands
  ),
  ranked AS (
    SELECT *,
      initcap(ngram) AS display_name
    FROM agg
    ORDER BY total_plays DESC
    LIMIT p_limit
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', display_name,
    'keyword', ngram,
    'islands', islands,
    'totalPlays', total_plays,
    'totalPlayers', total_players,
    'peakCCU', peak_ccu,
    'avgD1', ROUND(COALESCE(avg_d1, 0)::numeric, 4),
    'value', total_plays,
    'label', islands || ' islands · ' || 
      CASE WHEN total_plays >= 1000000 THEN ROUND(total_plays::numeric / 1000000, 1) || 'M'
           WHEN total_plays >= 1000 THEN ROUND(total_plays::numeric / 1000, 1) || 'K'
           ELSE total_plays::text END || ' plays'
  )), '[]'::jsonb) INTO v_result
  FROM ranked;

  RETURN jsonb_build_object('trendingTopics', v_result);
END;
$fn$;


-- ============================================================
-- RPC 7: report_finalize_wow_movers
-- Top risers and decliners (WoW delta comparison)
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_wow_movers(
  p_report_id uuid,
  p_prev_report_id uuid,
  p_limit int DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '30s'
AS $fn$
  WITH curr AS (
    SELECT island_code, title, creator_code, category, week_plays, week_unique
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
  ),
  prev AS (
    SELECT island_code, week_plays, week_unique
    FROM discover_report_islands
    WHERE report_id = p_prev_report_id AND status = 'reported'
  ),
  deltas AS (
    SELECT c.island_code, c.title, c.creator_code, c.category,
           (COALESCE(c.week_plays, 0) - COALESCE(p.week_plays, 0)) AS delta_plays
    FROM curr c
    JOIN prev p ON p.island_code = c.island_code
  ),
  risers AS (
    SELECT * FROM deltas WHERE delta_plays > 0 ORDER BY delta_plays DESC LIMIT p_limit
  ),
  decliners AS (
    SELECT * FROM deltas WHERE delta_plays < 0 ORDER BY delta_plays ASC LIMIT p_limit
  )
  SELECT jsonb_build_object(
    'topRisers', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', island_code, 'name', COALESCE(title, island_code),
      'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
      'value', delta_plays, 'label', '+' || delta_plays || ' plays'
    )), '[]') FROM risers),
    'topDecliners', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', island_code, 'name', COALESCE(title, island_code),
      'creator', creator_code, 'category', COALESCE(category, 'Fortnite UGC'),
      'value', ABS(delta_plays), 'label', delta_plays || ' plays'
    )), '[]') FROM decliners)
  );
$fn$;
