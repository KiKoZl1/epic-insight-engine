-- Public "Discovery Intelligence" tables.
-- These are precomputed snapshots designed to be readable by anon users (public pages),
-- without exposing internal exposure tables directly.

-- 1) Panel classification (tiers)
CREATE TABLE IF NOT EXISTS public.discovery_panel_tiers (
  panel_name TEXT PRIMARY KEY,
  tier INT NOT NULL CHECK (tier >= 1 AND tier <= 3),
  label TEXT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed known panels (idempotent)
INSERT INTO public.discovery_panel_tiers (panel_name, tier, label)
VALUES
  -- Tier 1: premium/curated panels (coletaveis hoje)
  ('Homebar_Default', 1, 'Homebar'),
  ('Nested_EpicsPicks', 1, 'Epic''s Picks'),
  ('Nested_TrendingInDiscover', 1, 'Trending in Discover'),
  ('Nested_TopRated', 1, 'Top Rated'),
  ('Nested_NewAndTopRated', 1, 'Top Rated'),

  -- Tier 2: novelty/update funnels (useful for emerging)
  ('NewAndUpdated1', 2, 'New and Updated'),
  ('Nested_NewUpdatesThisWeek', 2, 'New Updates'),
  ('UpdatedIslandsFromCreators', 2, 'Updated Islands')
ON CONFLICT (panel_name) DO UPDATE
SET tier = EXCLUDED.tier,
    label = EXCLUDED.label,
    updated_at = now();

ALTER TABLE public.discovery_panel_tiers ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_panel_tiers'
      AND policyname='select_discovery_panel_tiers_public'
  ) THEN
    CREATE POLICY select_discovery_panel_tiers_public
      ON public.discovery_panel_tiers FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

-- 2) Public snapshot: premium panels "now" (per rank)
CREATE TABLE IF NOT EXISTS public.discovery_public_premium_now (
  as_of TIMESTAMPTZ NOT NULL,
  region TEXT NOT NULL,
  surface_name TEXT NOT NULL,
  panel_name TEXT NOT NULL,
  panel_display_name TEXT NULL,
  panel_type TEXT NULL,
  rank INT NOT NULL,
  link_code TEXT NOT NULL,
  link_code_type TEXT NOT NULL,
  ccu INT NULL,
  title TEXT NULL,
  creator_code TEXT NULL,
  PRIMARY KEY (as_of, region, surface_name, panel_name, rank)
);

CREATE INDEX IF NOT EXISTS discovery_public_premium_now_lookup_idx
  ON public.discovery_public_premium_now (region, surface_name, panel_name, rank);

ALTER TABLE public.discovery_public_premium_now ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_public_premium_now'
      AND policyname='select_discovery_public_premium_now_public'
  ) THEN
    CREATE POLICY select_discovery_public_premium_now_public
      ON public.discovery_public_premium_now FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

-- 3) Public snapshot: emerging islands "now" (per region+surface)
CREATE TABLE IF NOT EXISTS public.discovery_public_emerging_now (
  as_of TIMESTAMPTZ NOT NULL,
  region TEXT NOT NULL,
  surface_name TEXT NOT NULL,
  link_code TEXT NOT NULL,
  link_code_type TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  minutes_6h INT NOT NULL,
  minutes_24h INT NOT NULL,
  best_rank_24h INT NULL,
  panels_24h INT NOT NULL,
  premium_panels_24h INT NOT NULL,
  reentries_24h INT NOT NULL,
  score DOUBLE PRECISION NOT NULL,
  title TEXT NULL,
  creator_code TEXT NULL,
  PRIMARY KEY (as_of, region, surface_name, link_code)
);

CREATE INDEX IF NOT EXISTS discovery_public_emerging_now_lookup_idx
  ON public.discovery_public_emerging_now (region, surface_name, score DESC);

ALTER TABLE public.discovery_public_emerging_now ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_public_emerging_now'
      AND policyname='select_discovery_public_emerging_now_public'
  ) THEN
    CREATE POLICY select_discovery_public_emerging_now_public
      ON public.discovery_public_emerging_now FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

-- 4) Public snapshot: pollution/spam creators "now"
CREATE TABLE IF NOT EXISTS public.discovery_public_pollution_creators_now (
  as_of TIMESTAMPTZ NOT NULL,
  creator_code TEXT NOT NULL,
  duplicate_clusters_7d INT NOT NULL,
  duplicate_islands_7d INT NOT NULL,
  duplicates_over_min INT NOT NULL,
  spam_score DOUBLE PRECISION NOT NULL,
  sample_titles TEXT[] NULL,
  PRIMARY KEY (as_of, creator_code)
);

CREATE INDEX IF NOT EXISTS discovery_public_pollution_creators_now_score_idx
  ON public.discovery_public_pollution_creators_now (spam_score DESC);

ALTER TABLE public.discovery_public_pollution_creators_now ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_public_pollution_creators_now'
      AND policyname='select_discovery_public_pollution_creators_now_public'
  ) THEN
    CREATE POLICY select_discovery_public_pollution_creators_now_public
      ON public.discovery_public_pollution_creators_now FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

-- 5) Title normalization helper (cheap duplicate clustering)
CREATE OR REPLACE FUNCTION public.normalize_island_title_for_dup(p_title TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    NULLIF(
      regexp_replace(
        regexp_replace(lower(coalesce(p_title,'')), '[^a-z0-9]+', ' ', 'g'),
        '\s+', ' ', 'g'
      ),
      ''
    );
$$;

-- 6) Compute and publish the public intel snapshots
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

  -- Replace snapshots atomically (small tables)
  DELETE FROM public.discovery_public_premium_now;
  DELETE FROM public.discovery_public_emerging_now;
  DELETE FROM public.discovery_public_pollution_creators_now;

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
    c.title,
    c.creator_code
  FROM public.discovery_exposure_rank_segments s
  JOIN public.discovery_exposure_targets t ON t.id = s.target_id
  JOIN public.discovery_panel_tiers pt ON pt.panel_name = s.panel_name AND pt.tier = 1
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
      c.target_id,
      c.link_code,
      COUNT(*)::int AS reentries_24h
    FROM candidates c
    JOIN public.discovery_exposure_presence_events e
      ON e.target_id = c.target_id AND e.link_code = c.link_code
    WHERE e.event_type = 'enter'
      AND e.ts >= v_as_of - interval '24 hours'
    GROUP BY c.target_id, c.link_code
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
      COALESCE(ch.reentries_24h, 0) AS reentries_24h,
      (
        (s.minutes_6h * 2.0) +
        (s.minutes_24h * 0.5) +
        (s.premium_panels_24h * 30.0) +
        (CASE WHEN s.best_rank_24h IS NULL THEN 0 ELSE GREATEST(0, 60 - (s.best_rank_24h * 3)) END) -
        (COALESCE(ch.reentries_24h, 0) * 2.0)
      ) AS score
    FROM seg_24h s
    LEFT JOIN churn ch ON ch.target_id = s.target_id AND ch.link_code = s.link_code
  ),
  ranked AS (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY region, surface_name ORDER BY score DESC) AS rn
    FROM scored
  )
  INSERT INTO public.discovery_public_emerging_now (
    as_of, region, surface_name, link_code, link_code_type,
    first_seen_at, minutes_6h, minutes_24h, best_rank_24h,
    panels_24h, premium_panels_24h, reentries_24h, score,
    title, creator_code
  )
  SELECT
    v_as_of,
    r.region,
    r.surface_name,
    r.link_code,
    r.link_code_type,
    r.first_seen_at,
    r.minutes_6h,
    r.minutes_24h,
    r.best_rank_24h,
    r.panels_24h,
    r.premium_panels_24h,
    r.reentries_24h,
    r.score,
    c.title,
    c.creator_code
  FROM ranked r
  LEFT JOIN public.discover_islands_cache c ON c.island_code = r.link_code
  WHERE r.rn <= 100;
  GET DIAGNOSTICS v_emerging_rows = ROW_COUNT;

  -- Pollution creators: duplicate clusters by normalized title among islands seen in Discovery in last 7 days.
  WITH active AS (
    SELECT DISTINCT
      ls.link_code
    FROM public.discovery_exposure_link_state ls
    WHERE ls.link_code_type = 'island'
      AND ls.last_seen_at >= v_as_of - interval '7 days'
  ),
  meta AS (
    SELECT
      c.creator_code,
      public.normalize_island_title_for_dup(c.title) AS norm_title,
      c.title
    FROM active a
    JOIN public.discover_islands_cache c ON c.island_code = a.link_code
    WHERE c.creator_code IS NOT NULL
      AND c.title IS NOT NULL
  ),
  clusters AS (
    SELECT
      creator_code,
      norm_title,
      COUNT(*)::int AS cnt,
      ARRAY_AGG(DISTINCT title ORDER BY title) AS titles
    FROM meta
    WHERE norm_title IS NOT NULL
    GROUP BY creator_code, norm_title
    HAVING COUNT(*) >= 2
  ),
  agg AS (
    SELECT
      creator_code,
      COUNT(*)::int AS duplicate_clusters_7d,
      SUM(cnt)::int AS duplicate_islands_7d,
      (SUM(cnt) - COUNT(*))::int AS duplicates_over_min,
      -- simple score: clusters weighted + extra duplicates weighted
      (COUNT(*) * 10.0) + ((SUM(cnt) - COUNT(*)) * 3.0) AS spam_score,
      (ARRAY_AGG((titles)[1] ORDER BY cnt DESC))[1:5] AS sample_titles
    FROM clusters
    GROUP BY creator_code
  )
  INSERT INTO public.discovery_public_pollution_creators_now (
    as_of, creator_code, duplicate_clusters_7d, duplicate_islands_7d, duplicates_over_min, spam_score, sample_titles
  )
  SELECT
    v_as_of, a.creator_code, a.duplicate_clusters_7d, a.duplicate_islands_7d, a.duplicates_over_min, a.spam_score, a.sample_titles
  FROM agg a
  ORDER BY a.spam_score DESC
  LIMIT 200;
  GET DIAGNOSTICS v_pollution_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'as_of', v_as_of,
    'premium_rows', v_premium_rows,
    'emerging_rows', v_emerging_rows,
    'pollution_rows', v_pollution_rows
  );
END;
$$;
