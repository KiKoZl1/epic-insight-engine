-- Improve compute_discovery_public_intel:
-- - use TRUNCATE instead of DELETE (less bloat/locking)
-- - add timeouts so it never blocks the whole API
-- - enrich titles/creator codes from discover_link_metadata (covers islands + collections)

CREATE OR REPLACE FUNCTION public.compute_discovery_public_intel(p_as_of TIMESTAMPTZ DEFAULT now())
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_as_of TIMESTAMPTZ := COALESCE(p_as_of, now());
  v_premium_rows INT := 0;
  v_emerging_rows INT := 0;
  v_pollution_rows INT := 0;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Hard caps: prevent long blocking/lock waits from taking down PostgREST.
  PERFORM set_config('statement_timeout', '30s', true);
  PERFORM set_config('lock_timeout', '2s', true);

  -- Replace snapshots atomically (small tables)
  TRUNCATE TABLE public.discovery_public_premium_now;
  TRUNCATE TABLE public.discovery_public_emerging_now;
  TRUNCATE TABLE public.discovery_public_pollution_creators_now;

  -- Premium "now" (Tier 1 panels, open rank segments)
  INSERT INTO public.discovery_public_premium_now (
    as_of, region, surface_name, panel_name, panel_display_name, panel_type,
    rank, link_code, link_code_type, ccu, title, creator_code
  )
  SELECT
    v_as_of,
    t.region,
    t.surface_name,
    s.panel_name,
    s.panel_display_name,
    s.panel_type,
    s.rank,
    s.link_code,
    s.link_code_type,
    COALESCE(s.ccu_end, s.ccu_max, s.ccu_start) AS ccu,
    COALESCE(m.title, c.title) AS title,
    COALESCE(m.support_code, c.creator_code) AS creator_code
  FROM public.discovery_exposure_rank_segments s
  JOIN public.discovery_exposure_targets t ON t.id = s.target_id
  JOIN public.discovery_panel_tiers pt ON pt.panel_name = s.panel_name AND pt.tier = 1
  LEFT JOIN public.discover_link_metadata m ON m.link_code = s.link_code
  LEFT JOIN public.discover_islands_cache c
    ON c.island_code = s.link_code AND s.link_code_type = 'island'
  WHERE s.end_ts IS NULL;
  GET DIAGNOSTICS v_premium_rows = ROW_COUNT;

  -- Emerging "now": islands whose FIRST exposure is recent, scored by exposure + premium touches + best rank + churn.
  WITH candidates AS (
    SELECT
      ls.target_id,
      t.region,
      t.surface_name,
      ls.link_code,
      ls.link_code_type,
      ls.first_seen_at
    FROM public.discovery_exposure_link_state ls
    JOIN public.discovery_exposure_targets t ON t.id = ls.target_id
    WHERE ls.first_seen_at >= v_as_of - interval '24 hours'
      AND ls.link_code_type = 'island'
  ),
  seg_24h AS (
    SELECT
      c.target_id,
      c.region,
      c.surface_name,
      c.link_code,
      MIN(c.first_seen_at) AS first_seen_at,
      -- minutes in windows (intersection with [as_of-window, as_of])
      SUM(
        GREATEST(
          0,
          EXTRACT(epoch FROM (LEAST(COALESCE(s.end_ts, v_as_of), v_as_of) - GREATEST(s.start_ts, v_as_of - interval '24 hours')))
        ) / 60
      )::int AS minutes_24h,
      SUM(
        GREATEST(
          0,
          EXTRACT(epoch FROM (LEAST(COALESCE(s.end_ts, v_as_of), v_as_of) - GREATEST(s.start_ts, v_as_of - interval '6 hours')))
        ) / 60
      )::int AS minutes_6h,
      MIN(s.best_rank)::int AS best_rank_24h,
      COUNT(DISTINCT s.panel_name)::int AS panels_24h,
      COUNT(DISTINCT CASE WHEN pt.tier = 1 THEN s.panel_name END)::int AS premium_panels_24h
    FROM candidates c
    JOIN public.discovery_exposure_presence_segments s
      ON s.target_id = c.target_id AND s.link_code = c.link_code
    LEFT JOIN public.discovery_panel_tiers pt ON pt.panel_name = s.panel_name
    WHERE s.last_seen_ts >= v_as_of - interval '24 hours'
    GROUP BY c.target_id, c.region, c.surface_name, c.link_code
  ),
  churn AS (
    SELECT
      e.target_id,
      e.link_code,
      COUNT(*) FILTER (WHERE e.event_type = 'enter')::int AS reentries_24h
    FROM public.discovery_exposure_presence_events e
    WHERE e.ts >= v_as_of - interval '24 hours'
    GROUP BY e.target_id, e.link_code
  ),
  scored AS (
    SELECT
      s.target_id,
      s.region,
      s.surface_name,
      s.link_code,
      'island'::text AS link_code_type,
      s.first_seen_at,
      s.minutes_6h,
      s.minutes_24h,
      s.best_rank_24h,
      s.panels_24h,
      s.premium_panels_24h,
      COALESCE(c.reentries_24h, 0) AS reentries_24h,
      (
        s.minutes_24h
        + (s.premium_panels_24h * 30)
        + (CASE WHEN s.best_rank_24h IS NULL THEN 0 ELSE (100.0 / GREATEST(1, s.best_rank_24h)) END)
        + (COALESCE(c.reentries_24h, 0) * 5)
      )::double precision AS score
    FROM seg_24h s
    LEFT JOIN churn c ON c.target_id = s.target_id AND c.link_code = s.link_code
  )
  INSERT INTO public.discovery_public_emerging_now (
    as_of, region, surface_name, link_code, link_code_type,
    first_seen_at, minutes_6h, minutes_24h, best_rank_24h, panels_24h,
    premium_panels_24h, reentries_24h, score, title, creator_code
  )
  SELECT
    v_as_of,
    s.region,
    s.surface_name,
    s.link_code,
    s.link_code_type,
    s.first_seen_at,
    s.minutes_6h,
    s.minutes_24h,
    s.best_rank_24h,
    s.panels_24h,
    s.premium_panels_24h,
    s.reentries_24h,
    s.score,
    COALESCE(m.title, c.title) AS title,
    COALESCE(m.support_code, c.creator_code) AS creator_code
  FROM scored s
  LEFT JOIN public.discover_link_metadata m ON m.link_code = s.link_code
  LEFT JOIN public.discover_islands_cache c ON c.island_code = s.link_code
  ORDER BY s.score DESC
  LIMIT 200;
  GET DIAGNOSTICS v_emerging_rows = ROW_COUNT;

  -- Pollution/spam creators "now" (cheap heuristics): cluster by normalized title + thumb URL for islands seen in last 7d.
  WITH recent AS (
    SELECT
      ps.link_code,
      COALESCE(m.support_code, c.creator_code) AS creator_code,
      COALESCE(m.title, c.title) AS title,
      m.image_url AS image_url
    FROM public.discovery_exposure_presence_segments ps
    JOIN public.discovery_exposure_targets t ON t.id = ps.target_id
    LEFT JOIN public.discover_link_metadata m ON m.link_code = ps.link_code
    LEFT JOIN public.discover_islands_cache c ON c.island_code = ps.link_code
    WHERE ps.start_ts >= v_as_of - interval '7 days'
      AND ps.link_code_type = 'island'
      AND t.last_ok_tick_at IS NOT NULL
  ),
  keyed AS (
    SELECT
      creator_code,
      normalize_island_title_for_dup(title) AS norm_title,
      image_url,
      link_code,
      title
    FROM recent
    WHERE creator_code IS NOT NULL
  ),
  clusters AS (
    SELECT
      creator_code,
      norm_title,
      image_url,
      COUNT(DISTINCT link_code)::int AS islands
    FROM keyed
    WHERE norm_title IS NOT NULL
    GROUP BY creator_code, norm_title, image_url
    HAVING COUNT(DISTINCT link_code) >= 2
  ),
  per_creator AS (
    SELECT
      creator_code,
      COUNT(*)::int AS duplicate_clusters_7d,
      SUM(islands)::int AS duplicate_islands_7d,
      SUM(GREATEST(0, islands - 2))::int AS duplicates_over_min,
      (
        COUNT(*) * 2.0
        + SUM(islands) * 1.0
        + SUM(GREATEST(0, islands - 2)) * 1.5
      )::double precision AS spam_score
    FROM clusters
    GROUP BY creator_code
    ORDER BY spam_score DESC
    LIMIT 200
  )
  INSERT INTO public.discovery_public_pollution_creators_now (
    as_of, creator_code, duplicate_clusters_7d, duplicate_islands_7d, duplicates_over_min, spam_score, sample_titles
  )
  SELECT
    v_as_of,
    p.creator_code,
    p.duplicate_clusters_7d,
    p.duplicate_islands_7d,
    p.duplicates_over_min,
    p.spam_score,
    (
      SELECT array_agg(DISTINCT k.title ORDER BY k.title) FILTER (WHERE k.title IS NOT NULL)
      FROM keyed k
      WHERE k.creator_code = p.creator_code
      LIMIT 10
    ) AS sample_titles
  FROM per_creator p;
  GET DIAGNOSTICS v_pollution_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'as_of', v_as_of,
    'premium_rows', v_premium_rows,
    'emerging_rows', v_emerging_rows,
    'pollution_rows', v_pollution_rows
  );
END;
$$;

