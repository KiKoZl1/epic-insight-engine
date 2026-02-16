
-- ============================================================
-- RPC 1: report_finalize_tool_split
-- UEFN vs FNC metrics comparison
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_tool_split(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
SET statement_timeout = '45s'
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'toolSplit', (
      SELECT jsonb_agg(row_to_json(t))
      FROM (
        SELECT
          COALESCE(ri.created_in, 'Unknown') AS tool,
          COUNT(*)::int AS island_count,
          COALESCE(AVG(ri.week_plays), 0)::numeric(12,1) AS avg_plays,
          COALESCE(AVG(ri.week_unique), 0)::numeric(12,1) AS avg_unique,
          COALESCE(AVG(ri.week_minutes), 0)::numeric(12,1) AS avg_minutes,
          COALESCE(AVG(ri.week_minutes_per_player_avg), 0)::numeric(6,2) AS avg_minutes_per_player,
          COALESCE(AVG(ri.week_peak_ccu_max), 0)::numeric(12,1) AS avg_peak_ccu,
          COALESCE(AVG(ri.week_d1_avg), 0)::numeric(6,4) AS avg_d1,
          COALESCE(AVG(ri.week_d7_avg), 0)::numeric(6,4) AS avg_d7,
          COALESCE(SUM(ri.week_plays), 0)::bigint AS total_plays,
          COALESCE(SUM(ri.week_unique), 0)::bigint AS total_unique,
          COALESCE(SUM(ri.week_favorites), 0)::bigint AS total_favorites,
          COALESCE(SUM(ri.week_recommends), 0)::bigint AS total_recommends
        FROM discover_report_islands ri
        WHERE ri.report_id = p_report_id
          AND ri.status = 'reported'
          AND ri.created_in IS NOT NULL
        GROUP BY COALESCE(ri.created_in, 'Unknown')
        ORDER BY total_plays DESC
      ) t
    ),
    'capacityAnalysis', (
      SELECT jsonb_agg(row_to_json(c))
      FROM (
        SELECT
          CASE
            WHEN dic.max_players IS NULL THEN 'Unknown'
            WHEN dic.max_players <= 1 THEN 'Solo (1)'
            WHEN dic.max_players <= 2 THEN 'Duo (2)'
            WHEN dic.max_players <= 4 THEN 'Squad (3-4)'
            WHEN dic.max_players <= 8 THEN 'Party (5-8)'
            WHEN dic.max_players <= 16 THEN 'Large (9-16)'
            ELSE 'Massive (17+)'
          END AS capacity_tier,
          COUNT(*)::int AS island_count,
          COALESCE(AVG(ri.week_plays), 0)::numeric(12,1) AS avg_plays,
          COALESCE(AVG(ri.week_unique), 0)::numeric(12,1) AS avg_unique,
          COALESCE(AVG(ri.week_d1_avg), 0)::numeric(6,4) AS avg_d1,
          COALESCE(AVG(ri.week_d7_avg), 0)::numeric(6,4) AS avg_d7,
          COALESCE(AVG(ri.week_minutes_per_player_avg), 0)::numeric(6,2) AS avg_minutes_per_player
        FROM discover_report_islands ri
        JOIN discover_islands_cache dic ON dic.island_code = ri.island_code
        WHERE ri.report_id = p_report_id
          AND ri.status = 'reported'
        GROUP BY capacity_tier
        ORDER BY avg_plays DESC
      ) c
    )
  ) INTO result;

  RETURN result;
END;
$$;

-- ============================================================
-- RPC 2: report_finalize_rookies
-- New creators this week with best performing islands
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_rookies(p_report_id uuid, p_limit int DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
SET statement_timeout = '45s'
AS $$
DECLARE
  result jsonb;
  v_week_start date;
  v_week_end date;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  SELECT jsonb_build_object(
    'rookieCreators', (
      SELECT jsonb_agg(row_to_json(r))
      FROM (
        SELECT
          dic.creator_code,
          COUNT(DISTINCT ri.island_code)::int AS island_count,
          MAX(ri.week_plays)::int AS best_plays,
          MAX(ri.week_unique)::int AS best_unique,
          MAX(ri.week_peak_ccu_max)::int AS best_ccu,
          SUM(ri.week_plays)::bigint AS total_plays,
          (array_agg(ri.title ORDER BY ri.week_plays DESC NULLS LAST))[1] AS best_island_title,
          (array_agg(ri.island_code ORDER BY ri.week_plays DESC NULLS LAST))[1] AS best_island_code
        FROM discover_report_islands ri
        JOIN discover_islands_cache dic ON dic.island_code = ri.island_code
        WHERE ri.report_id = p_report_id
          AND ri.status = 'reported'
          AND dic.first_seen_at >= v_week_start::timestamptz
          AND dic.first_seen_at < (v_week_end + interval '1 day')::timestamptz
          AND dic.creator_code IS NOT NULL
        GROUP BY dic.creator_code
        ORDER BY total_plays DESC
        LIMIT p_limit
      ) r
    ),
    'totalRookieCreators', (
      SELECT COUNT(DISTINCT dic.creator_code)::int
      FROM discover_report_islands ri
      JOIN discover_islands_cache dic ON dic.island_code = ri.island_code
      WHERE ri.report_id = p_report_id
        AND ri.status = 'reported'
        AND dic.first_seen_at >= v_week_start::timestamptz
        AND dic.first_seen_at < (v_week_end + interval '1 day')::timestamptz
        AND dic.creator_code IS NOT NULL
    ),
    'totalRookieIslands', (
      SELECT COUNT(*)::int
      FROM discover_report_islands ri
      JOIN discover_islands_cache dic ON dic.island_code = ri.island_code
      WHERE ri.report_id = p_report_id
        AND ri.status = 'reported'
        AND dic.first_seen_at >= v_week_start::timestamptz
        AND dic.first_seen_at < (v_week_end + interval '1 day')::timestamptz
    )
  ) INTO result;

  RETURN result;
END;
$$;

-- ============================================================
-- RPC 3: report_finalize_exposure_analysis
-- Multi-panel presence, panel loyalty, version enrichment
-- ============================================================
CREATE OR REPLACE FUNCTION public.report_finalize_exposure_analysis(p_report_id uuid, p_days int DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
SET statement_timeout = '45s'
AS $$
DECLARE
  result jsonb;
  v_week_start date;
  v_week_end date;
BEGIN
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM discover_reports WHERE id = p_report_id;

  SELECT jsonb_build_object(
    'multiPanelPresence', (
      SELECT jsonb_agg(row_to_json(mp))
      FROM (
        SELECT
          r.link_code,
          r.link_code_type,
          COUNT(DISTINCT r.panel_name)::int AS panels_distinct,
          array_agg(DISTINCT r.panel_name ORDER BY r.panel_name) AS panel_names,
          COALESCE(dic.title, r.link_code) AS title,
          dic.creator_code,
          dic.image_url
        FROM discovery_exposure_rollup_daily r
        JOIN discover_islands_cache dic ON dic.island_code = r.link_code
        WHERE r.date >= v_week_start::text
          AND r.date <= v_week_end::text
          AND r.link_code_type = 'island'
        GROUP BY r.link_code, r.link_code_type, dic.title, dic.creator_code, dic.image_url
        HAVING COUNT(DISTINCT r.panel_name) >= 2
        ORDER BY panels_distinct DESC
        LIMIT 10
      ) mp
    ),
    'panelLoyalty', (
      SELECT jsonb_agg(row_to_json(pl))
      FROM (
        SELECT
          r.link_code,
          r.panel_name,
          SUM(r.minutes_exposed)::int AS total_minutes_in_panel,
          COALESCE(dic.title, r.link_code) AS title,
          dic.creator_code,
          dic.image_url
        FROM discovery_exposure_rollup_daily r
        JOIN discover_islands_cache dic ON dic.island_code = r.link_code
        WHERE r.date >= v_week_start::text
          AND r.date <= v_week_end::text
          AND r.link_code_type = 'island'
        GROUP BY r.link_code, r.panel_name, dic.title, dic.creator_code, dic.image_url
        ORDER BY total_minutes_in_panel DESC
        LIMIT 10
      ) pl
    ),
    'versionEnrichment', (
      SELECT jsonb_build_object(
        'avgVersion', COALESCE(AVG(dlm.version), 0)::numeric(6,1),
        'islandsWithVersion5Plus', COUNT(*) FILTER (WHERE dlm.version >= 5)::int,
        'totalWithVersion', COUNT(*) FILTER (WHERE dlm.version IS NOT NULL)::int,
        'versionDistribution', (
          SELECT jsonb_agg(row_to_json(vd))
          FROM (
            SELECT
              CASE
                WHEN dlm2.version = 1 THEN 'v1'
                WHEN dlm2.version BETWEEN 2 AND 5 THEN 'v2-5'
                WHEN dlm2.version BETWEEN 6 AND 10 THEN 'v6-10'
                WHEN dlm2.version BETWEEN 11 AND 20 THEN 'v11-20'
                WHEN dlm2.version > 20 THEN 'v21+'
                ELSE 'unknown'
              END AS version_tier,
              COUNT(*)::int AS count
            FROM discover_report_islands ri2
            JOIN discover_link_metadata dlm2 ON dlm2.link_code = ri2.island_code
            WHERE ri2.report_id = p_report_id
              AND ri2.status = 'reported'
              AND dlm2.version IS NOT NULL
            GROUP BY version_tier
            ORDER BY count DESC
          ) vd
        )
      )
      FROM discover_report_islands ri
      JOIN discover_link_metadata dlm ON dlm.link_code = ri.island_code
      WHERE ri.report_id = p_report_id
        AND ri.status = 'reported'
    ),
    'sacCoverage', (
      SELECT jsonb_build_object(
        'totalWithSAC', COUNT(*) FILTER (WHERE dlm.support_code IS NOT NULL AND dlm.support_code != '')::int,
        'totalChecked', COUNT(*)::int,
        'sacPct', CASE WHEN COUNT(*) > 0 THEN (COUNT(*) FILTER (WHERE dlm.support_code IS NOT NULL AND dlm.support_code != '')::numeric / COUNT(*)::numeric * 100)::numeric(5,1) ELSE 0 END
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
