
CREATE OR REPLACE FUNCTION public.report_finalize_exposure_efficiency(p_report_id uuid, p_limit integer DEFAULT 15)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  WITH exposure AS (
    SELECT
      ps.link_code,
      ps.link_code_type,
      ps.panel_name,
      ps.surface_name,
      SUM(EXTRACT(EPOCH FROM (COALESCE(ps.end_ts, ps.last_seen_ts) - ps.start_ts)) / 60.0) AS total_minutes_exposed,
      COUNT(DISTINCT ps.panel_name) AS panels_count,
      MIN(ps.best_rank) AS best_rank
    FROM discovery_exposure_presence_segments ps
    WHERE ps.start_ts >= (v_week_start - interval '1 day')::timestamptz
      AND ps.start_ts < (v_week_end + interval '1 day')::timestamptz
      AND ps.link_code_type = 'island'
    GROUP BY ps.link_code, ps.link_code_type, ps.panel_name, ps.surface_name
  ),
  exposure_agg AS (
    SELECT
      link_code,
      SUM(total_minutes_exposed) AS total_minutes_exposed,
      COUNT(DISTINCT panel_name) AS distinct_panels,
      MIN(best_rank) AS best_rank
    FROM exposure
    GROUP BY link_code
    HAVING SUM(total_minutes_exposed) > 5
  ),
  -- Per-panel breakdown for each island
  panel_detail AS (
    SELECT
      link_code,
      panel_name,
      SUM(total_minutes_exposed)::int AS minutes,
      COUNT(*)::int AS appearances,
      MIN(best_rank) AS best_rank
    FROM exposure
    GROUP BY link_code, panel_name
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
    JOIN discover_report_islands ri ON ri.island_code = e.link_code AND ri.report_id = p_report_id
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
