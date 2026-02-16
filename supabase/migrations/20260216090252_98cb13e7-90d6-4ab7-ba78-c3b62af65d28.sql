
CREATE OR REPLACE FUNCTION public.report_finalize_exposure_analysis(p_report_id uuid, p_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
          -- Per-panel minutes breakdown as JSON array
          (
            SELECT jsonb_agg(jsonb_build_object(
              'panel', sub.panel_name,
              'minutes', sub.mins,
              'appearances', sub.apps,
              'best_rank', sub.best_r
            ) ORDER BY sub.mins DESC)
            FROM (
              SELECT r2.panel_name, SUM(r2.minutes_exposed)::int AS mins,
                     SUM(r2.appearances)::int AS apps, MIN(r2.best_rank) AS best_r
              FROM discovery_exposure_rollup_daily r2
              WHERE r2.link_code = r.link_code AND r2.date >= v_week_start AND r2.date <= v_week_end
              GROUP BY r2.panel_name
            ) sub
          ) AS panel_breakdown,
          COALESCE(dlm.title, dic.title, r.link_code) AS title,
          COALESCE(dlm.support_code, dlm.creator_name, dic.creator_code) AS creator_code,
          COALESCE(dlm.image_url, dic.image_url) AS image_url
        FROM discovery_exposure_rollup_daily r
        LEFT JOIN discover_islands_cache dic ON dic.island_code = r.link_code
        LEFT JOIN discover_link_metadata dlm ON dlm.link_code = r.link_code
        WHERE r.date >= v_week_start
          AND r.date <= v_week_end
          AND r.link_code_type = 'island'
        GROUP BY r.link_code, r.link_code_type, dlm.title, dic.title, dlm.support_code, dlm.creator_name, dic.creator_code, dlm.image_url, dic.image_url
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
          SUM(r.appearances)::int AS total_appearances,
          MIN(r.best_rank) AS best_rank,
          COALESCE(dlm.title, dic.title, r.link_code) AS title,
          COALESCE(dlm.support_code, dlm.creator_name, dic.creator_code) AS creator_code,
          COALESCE(dlm.image_url, dic.image_url) AS image_url
        FROM discovery_exposure_rollup_daily r
        LEFT JOIN discover_islands_cache dic ON dic.island_code = r.link_code
        LEFT JOIN discover_link_metadata dlm ON dlm.link_code = r.link_code
        WHERE r.date >= v_week_start
          AND r.date <= v_week_end
          AND r.link_code_type = 'island'
        GROUP BY r.link_code, r.panel_name, dlm.title, dic.title, dlm.support_code, dlm.creator_name, dic.creator_code, dlm.image_url, dic.image_url
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
