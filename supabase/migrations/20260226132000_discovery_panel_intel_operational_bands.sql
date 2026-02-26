CREATE OR REPLACE FUNCTION public.compute_discovery_panel_intel_snapshot(
  p_target_id uuid,
  p_window_days int DEFAULT 14,
  p_panel_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_window_days int := GREATEST(1, LEAST(COALESCE(p_window_days, 14), 60));
  v_window_start timestamptz := now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_window_days, 14), 60)));
  v_region text;
  v_surface text;
  v_upserted int := 0;
  v_processed_panels int := 0;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT t.region, t.surface_name
  INTO v_region, v_surface
  FROM public.discovery_exposure_targets t
  WHERE t.id = p_target_id
  LIMIT 1;

  IF v_region IS NULL OR v_surface IS NULL THEN
    RAISE EXCEPTION 'target_not_found';
  END IF;

  WITH panel_source AS (
    SELECT DISTINCT s.panel_name
    FROM public.discovery_exposure_presence_segments s
    WHERE s.target_id = p_target_id
      AND s.link_code_type = 'island'
      AND s.start_ts < v_now
      AND COALESCE(s.end_ts, s.last_seen_ts, v_now) > v_window_start
      AND (p_panel_name IS NULL OR s.panel_name = p_panel_name)
    UNION
    SELECT p_panel_name
    WHERE p_panel_name IS NOT NULL
  ),
  stint_base AS (
    SELECT
      s.panel_name,
      s.link_code,
      GREATEST(s.start_ts, v_window_start) AS overlap_start,
      LEAST(COALESCE(s.end_ts, s.last_seen_ts, v_now), v_now) AS overlap_end,
      s.ccu_start,
      s.ccu_end,
      s.ccu_max,
      s.end_ts,
      s.closed_reason
    FROM public.discovery_exposure_presence_segments s
    WHERE s.target_id = p_target_id
      AND s.link_code_type = 'island'
      AND s.start_ts < v_now
      AND COALESCE(s.end_ts, s.last_seen_ts, v_now) > v_window_start
      AND (p_panel_name IS NULL OR s.panel_name = p_panel_name)
  ),
  stint_enriched AS (
    SELECT
      b.panel_name,
      b.link_code,
      EXTRACT(EPOCH FROM (b.overlap_end - b.overlap_start)) / 60.0 AS stint_minutes,
      b.ccu_start,
      b.ccu_end,
      b.ccu_max,
      b.end_ts,
      b.closed_reason,
      CASE
        WHEN (CASE WHEN b.ccu_start IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN b.ccu_end IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN b.ccu_max IS NOT NULL THEN 1 ELSE 0 END) = 0 THEN NULL
        ELSE (
          COALESCE(b.ccu_start, 0)::numeric
          + COALESCE(b.ccu_end, 0)::numeric
          + COALESCE(b.ccu_max, 0)::numeric
        ) / (
          (CASE WHEN b.ccu_start IS NOT NULL THEN 1 ELSE 0 END)
          + (CASE WHEN b.ccu_end IS NOT NULL THEN 1 ELSE 0 END)
          + (CASE WHEN b.ccu_max IS NOT NULL THEN 1 ELSE 0 END)
        )::numeric
      END AS ccu_ref
    FROM stint_base b
    WHERE b.overlap_end > b.overlap_start
  ),
  -- Operational benchmark: closed stints only, capped to 180m.
  -- This avoids persistent resident maps distorting the panel baseline.
  closed_stints AS (
    SELECT *
    FROM stint_enriched
    WHERE end_ts IS NOT NULL
      AND stint_minutes > 0
  ),
  closed_operational AS (
    SELECT *
    FROM closed_stints
    WHERE stint_minutes <= 180
  ),
  benchmark_stints AS (
    SELECT * FROM closed_operational
    UNION ALL
    SELECT c.*
    FROM closed_stints c
    WHERE NOT EXISTS (SELECT 1 FROM closed_operational)
  ),
  panel_core AS (
    SELECT
      e.panel_name,
      CASE
        WHEN SUM(e.stint_minutes) FILTER (WHERE e.ccu_ref IS NOT NULL) > 0
          THEN (
            SUM(e.ccu_ref * e.stint_minutes) FILTER (WHERE e.ccu_ref IS NOT NULL)
            / SUM(e.stint_minutes) FILTER (WHERE e.ccu_ref IS NOT NULL)
          )::double precision
        ELSE NULL
      END AS panel_avg_ccu
    FROM stint_enriched e
    GROUP BY e.panel_name
  ),
  panel_stint AS (
    SELECT
      b.panel_name,
      COUNT(*)::int AS sample_stints,
      COUNT(*)::int AS sample_closed_stints,
      AVG(b.stint_minutes)::double precision AS avg_exposure_minutes_per_stint,
      CASE
        WHEN COUNT(DISTINCT b.link_code) > 0
          THEN (SUM(b.stint_minutes) / COUNT(DISTINCT b.link_code)::numeric)::double precision
        ELSE 0
      END AS avg_exposure_minutes_per_map
    FROM benchmark_stints b
    GROUP BY b.panel_name
  ),
  panel_percentiles AS (
    SELECT
      b.panel_name,
      PERCENTILE_CONT(0.40) WITHIN GROUP (ORDER BY b.ccu_ref)
        FILTER (WHERE b.ccu_ref IS NOT NULL) AS ccu_p40,
      PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY b.ccu_ref)
        FILTER (WHERE b.ccu_ref IS NOT NULL) AS ccu_p80,
      PERCENTILE_CONT(0.40) WITHIN GROUP (ORDER BY b.stint_minutes) AS mins_p40,
      PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY b.stint_minutes) AS mins_p80,
      PERCENTILE_CONT(0.35) WITHIN GROUP (ORDER BY b.ccu_end)
        FILTER (WHERE b.ccu_end IS NOT NULL) AS removal_risk_ccu_floor,
      PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY b.stint_minutes) AS typical_exit_minutes
    FROM benchmark_stints b
    GROUP BY b.panel_name
  ),
  panel_events AS (
    SELECT
      e.panel_name,
      COUNT(*) FILTER (WHERE e.event_type = 'enter')::int AS entries_24h,
      COUNT(*) FILTER (WHERE e.event_type = 'exit')::int AS exits_24h
    FROM public.discovery_exposure_presence_events e
    WHERE e.target_id = p_target_id
      AND e.ts >= v_now - interval '24 hours'
      AND (p_panel_name IS NULL OR e.panel_name = p_panel_name)
    GROUP BY e.panel_name
  ),
  panel_replacements AS (
    SELECT
      r.panel_name,
      COUNT(*)::int AS replacements_24h
    FROM public.discovery_exposure_rank_segments r
    WHERE r.target_id = p_target_id
      AND r.closed_reason = 'replaced'
      AND COALESCE(r.end_ts, r.last_seen_ts, v_now) >= v_now - interval '24 hours'
      AND (p_panel_name IS NULL OR r.panel_name = p_panel_name)
    GROUP BY r.panel_name
  ),
  panel_active_now AS (
    SELECT
      s.panel_name,
      COUNT(DISTINCT s.link_code)::int AS active_maps_now
    FROM public.discovery_exposure_presence_segments s
    WHERE s.target_id = p_target_id
      AND s.link_code_type = 'island'
      AND s.end_ts IS NULL
      AND (p_panel_name IS NULL OR s.panel_name = p_panel_name)
    GROUP BY s.panel_name
  ),
  final_rows AS (
    SELECT
      p.panel_name,
      COALESCE(ps.sample_stints, 0) AS sample_stints,
      COALESCE(ps.sample_closed_stints, 0) AS sample_closed_stints,
      COALESCE(pa.active_maps_now, 0) AS active_maps_now,
      COALESCE(pe.entries_24h, 0) AS entries_24h,
      COALESCE(pe.exits_24h, 0) AS exits_24h,
      COALESCE(pr.replacements_24h, 0) AS replacements_24h,
      pc.panel_avg_ccu,
      ps.avg_exposure_minutes_per_stint,
      ps.avg_exposure_minutes_per_map,
      pp.ccu_p40,
      pp.ccu_p80,
      pp.mins_p40,
      pp.mins_p80,
      pp.removal_risk_ccu_floor,
      pp.typical_exit_minutes,
      CASE
        WHEN COALESCE(ps.sample_stints, 0) >= 120 AND COALESCE(ps.sample_closed_stints, 0) >= 40 THEN 'high'
        WHEN COALESCE(ps.sample_stints, 0) >= 60 AND COALESCE(ps.sample_closed_stints, 0) >= 20 THEN 'medium'
        ELSE 'low'
      END AS confidence,
      GREATEST(
        COALESCE(pp.removal_risk_ccu_floor, 0),
        COALESCE(pp.ccu_p40, 0)
      ) AS keep_alive_ccu_min,
      COALESCE(pp.typical_exit_minutes, pp.mins_p40, 0) AS keep_alive_minutes_min
    FROM panel_source p
    LEFT JOIN panel_core pc ON pc.panel_name = p.panel_name
    LEFT JOIN panel_stint ps ON ps.panel_name = p.panel_name
    LEFT JOIN panel_percentiles pp ON pp.panel_name = p.panel_name
    LEFT JOIN panel_events pe ON pe.panel_name = p.panel_name
    LEFT JOIN panel_replacements pr ON pr.panel_name = p.panel_name
    LEFT JOIN panel_active_now pa ON pa.panel_name = p.panel_name
  ),
  upserted AS (
    INSERT INTO public.discovery_panel_intel_snapshot (
      target_id,
      region,
      surface_name,
      panel_name,
      window_days,
      as_of,
      payload_json,
      sample_stints,
      sample_closed_stints,
      active_maps_now,
      confidence,
      updated_at
    )
    SELECT
      p_target_id,
      v_region,
      v_surface,
      f.panel_name,
      v_window_days,
      v_now,
      jsonb_build_object(
        'benchmark_mode', 'closed_stints_operational_180m',
        'panel_avg_ccu', CASE WHEN f.panel_avg_ccu IS NULL THEN NULL ELSE ROUND(f.panel_avg_ccu::numeric, 2) END,
        'avg_exposure_minutes_per_stint', CASE WHEN f.avg_exposure_minutes_per_stint IS NULL THEN NULL ELSE ROUND(f.avg_exposure_minutes_per_stint::numeric, 2) END,
        'avg_exposure_minutes_per_map', CASE WHEN f.avg_exposure_minutes_per_map IS NULL THEN NULL ELSE ROUND(f.avg_exposure_minutes_per_map::numeric, 2) END,
        'entries_24h', f.entries_24h,
        'exits_24h', f.exits_24h,
        'replacements_24h', f.replacements_24h,
        'ccu_bands', jsonb_build_object(
          'ruim_lt', CASE WHEN f.ccu_p40 IS NULL THEN NULL ELSE ROUND(f.ccu_p40::numeric, 2) END,
          'bom_gte', CASE WHEN f.ccu_p40 IS NULL THEN NULL ELSE ROUND(f.ccu_p40::numeric, 2) END,
          'excelente_gte', CASE WHEN f.ccu_p80 IS NULL THEN NULL ELSE ROUND(f.ccu_p80::numeric, 2) END
        ),
        'exposure_bands_minutes', jsonb_build_object(
          'ruim_lt', CASE WHEN f.mins_p40 IS NULL THEN NULL ELSE ROUND(f.mins_p40::numeric, 2) END,
          'bom_gte', CASE WHEN f.mins_p40 IS NULL THEN NULL ELSE ROUND(f.mins_p40::numeric, 2) END,
          'excelente_gte', CASE WHEN f.mins_p80 IS NULL THEN NULL ELSE ROUND(f.mins_p80::numeric, 2) END
        ),
        'removal_risk_ccu_floor', CASE WHEN f.removal_risk_ccu_floor IS NULL THEN NULL ELSE ROUND(f.removal_risk_ccu_floor::numeric, 2) END,
        'typical_exit_minutes', CASE WHEN f.typical_exit_minutes IS NULL THEN NULL ELSE ROUND(f.typical_exit_minutes::numeric, 2) END,
        'keep_alive_targets', jsonb_build_object(
          'ccu_min', CASE WHEN f.keep_alive_ccu_min = 0 THEN NULL ELSE ROUND(f.keep_alive_ccu_min::numeric, 2) END,
          'minutes_min', CASE WHEN f.keep_alive_minutes_min = 0 THEN NULL ELSE ROUND(f.keep_alive_minutes_min::numeric, 2) END
        ),
        'insights', jsonb_build_array(
          CASE
            WHEN COALESCE(f.ccu_p40, 0) >= 5000 THEN 'Pressao de entrada alta: o painel costuma exigir tracao forte de CCU para se manter.'
            WHEN COALESCE(f.ccu_p40, 0) >= 1500 THEN 'Pressao de entrada moderada: manter CCU acima da faixa media melhora permanencia.'
            ELSE 'Pressao de entrada baixa: consistencia de minutos expostos tende a pesar mais que pico isolado.'
          END,
          CASE
            WHEN COALESCE(f.replacements_24h, 0) >= 20 OR (COALESCE(f.entries_24h, 0) > 0 AND COALESCE(f.exits_24h, 0) >= COALESCE(f.entries_24h, 0))
              THEN 'Rotacao alta: o painel troca ilhas com frequencia e penaliza queda curta de tracao.'
            WHEN COALESCE(f.replacements_24h, 0) >= 8
              THEN 'Rotacao moderada: pequenas quedas podem gerar perda de posicao ao longo do dia.'
            ELSE 'Rotacao baixa: estabilidade maior para ilhas que sustentam tracao minima.'
          END,
          CASE
            WHEN COALESCE(f.keep_alive_ccu_min, 0) > 0 AND COALESCE(f.keep_alive_minutes_min, 0) > 0
              THEN 'Meta pratica: buscar pelo menos ' || ROUND(f.keep_alive_ccu_min)::text || ' CCU com ' || ROUND(f.keep_alive_minutes_min)::text || ' min de sustentacao.'
            ELSE 'Meta pratica: acumular exposicao continua e evitar quedas de CCU na janela inicial do painel.'
          END
        )
      ),
      f.sample_stints,
      f.sample_closed_stints,
      f.active_maps_now,
      f.confidence,
      now()
    FROM final_rows f
    ON CONFLICT (target_id, panel_name, window_days)
    DO UPDATE SET
      region = EXCLUDED.region,
      surface_name = EXCLUDED.surface_name,
      as_of = EXCLUDED.as_of,
      payload_json = EXCLUDED.payload_json,
      sample_stints = EXCLUDED.sample_stints,
      sample_closed_stints = EXCLUDED.sample_closed_stints,
      active_maps_now = EXCLUDED.active_maps_now,
      confidence = EXCLUDED.confidence,
      updated_at = now()
    RETURNING 1
  )
  SELECT COUNT(*)::int INTO v_upserted FROM upserted;

  v_processed_panels := COALESCE(v_upserted, 0);

  RETURN jsonb_build_object(
    'target_id', p_target_id,
    'window_days', v_window_days,
    'processed_panels', COALESCE(v_processed_panels, 0),
    'upserted_rows', COALESCE(v_upserted, 0),
    'as_of', v_now
  );
END;
$$;
