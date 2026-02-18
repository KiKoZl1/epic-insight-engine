-- Presence enter/exit events + persistent first/last seen (per target + link_code).
-- These power: emerging detection, churn/re-entry metrics, and near-real-time insights.

-- 1) Persistent first/last seen (per target + link_code)
CREATE TABLE IF NOT EXISTS public.discovery_exposure_link_state (
  target_id UUID NOT NULL REFERENCES public.discovery_exposure_targets(id) ON DELETE CASCADE,
  link_code TEXT NOT NULL,
  link_code_type TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (target_id, link_code)
);

CREATE INDEX IF NOT EXISTS discovery_exposure_link_state_last_seen_idx
  ON public.discovery_exposure_link_state (target_id, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS discovery_exposure_link_state_link_code_idx
  ON public.discovery_exposure_link_state (link_code, last_seen_at DESC);

ALTER TABLE public.discovery_exposure_link_state ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'discovery_exposure_link_state'
      AND policyname = 'select_discovery_exposure_link_state_authenticated'
  ) THEN
    CREATE POLICY select_discovery_exposure_link_state_authenticated
      ON public.discovery_exposure_link_state FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'discovery_exposure_link_state'
      AND policyname = 'all_discovery_exposure_link_state_service_role'
  ) THEN
    CREATE POLICY all_discovery_exposure_link_state_service_role
      ON public.discovery_exposure_link_state FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;
END $$;

-- 2) Presence enter/exit events
CREATE TABLE IF NOT EXISTS public.discovery_exposure_presence_events (
  id BIGSERIAL PRIMARY KEY,
  target_id UUID NOT NULL REFERENCES public.discovery_exposure_targets(id) ON DELETE CASCADE,
  tick_id UUID NOT NULL REFERENCES public.discovery_exposure_ticks(id) ON DELETE CASCADE,
  ts TIMESTAMPTZ NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
  surface_name TEXT NOT NULL,
  panel_name TEXT NOT NULL,
  panel_display_name TEXT NULL,
  panel_type TEXT NULL,
  feature_tags TEXT[] NULL,
  link_code TEXT NOT NULL,
  link_code_type TEXT NOT NULL,
  rank INT NULL,
  global_ccu INT NULL,
  closed_reason TEXT NULL
);

CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_target_ts_idx
  ON public.discovery_exposure_presence_events (target_id, ts DESC);

CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_link_ts_idx
  ON public.discovery_exposure_presence_events (link_code, ts DESC);

CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_panel_ts_idx
  ON public.discovery_exposure_presence_events (panel_name, ts DESC);

CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_type_ts_idx
  ON public.discovery_exposure_presence_events (event_type, ts DESC);

ALTER TABLE public.discovery_exposure_presence_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'discovery_exposure_presence_events'
      AND policyname = 'select_discovery_exposure_presence_events_authenticated'
  ) THEN
    CREATE POLICY select_discovery_exposure_presence_events_authenticated
      ON public.discovery_exposure_presence_events FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'discovery_exposure_presence_events'
      AND policyname = 'all_discovery_exposure_presence_events_service_role'
  ) THEN
    CREATE POLICY all_discovery_exposure_presence_events_service_role
      ON public.discovery_exposure_presence_events FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;
END $$;

-- 3) Extend apply_discovery_exposure_tick to:
-- - upsert discovery_exposure_link_state
-- - emit presence enter/exit events
CREATE OR REPLACE FUNCTION public.apply_discovery_exposure_tick(
  p_target_id UUID,
  p_tick_id UUID,
  p_tick_ts TIMESTAMPTZ,
  p_branch TEXT,
  p_test_variant_name TEXT,
  p_test_name TEXT,
  p_test_analytics_id TEXT,
  p_rows JSONB,
  p_duration_ms INT,
  p_correlation_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw_inserted INT := 0;
  v_presence_upserted INT := 0;
  v_presence_closed INT := 0;
  v_rank_replaced_closed INT := 0;
  v_rank_upserted INT := 0;
  v_rank_absent_closed INT := 0;
  v_panels_count INT := 0;
  v_entries_count INT := 0;
  v_events_entered INT := 0;
  v_events_exited INT := 0;
  v_link_state_upserted INT := 0;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Use a temp table so all statements can reference the parsed rows
  CREATE TEMP TABLE _tick_incoming ON COMMIT DROP AS
  SELECT
    x.surface_name::text AS surface_name,
    x.panel_name::text AS panel_name,
    NULLIF(x.panel_display_name::text, '') AS panel_display_name,
    NULLIF(x.panel_type::text, '') AS panel_type,
    x.feature_tags::text[] AS feature_tags,
    COALESCE(x.page_index::int, 0) AS page_index,
    GREATEST(x.rank::int, 1) AS rank,
    x.link_code::text AS link_code,
    x.link_code_type::text AS link_code_type,
    x.global_ccu::int AS global_ccu,
    x.is_visible::boolean AS is_visible,
    NULLIF(x.lock_status::text, '') AS lock_status,
    NULLIF(x.lock_status_reason::text, '') AS lock_status_reason
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS x(
    surface_name text, panel_name text, panel_display_name text, panel_type text,
    feature_tags text[], page_index int, rank int, link_code text, link_code_type text,
    global_ccu int, is_visible boolean, lock_status text, lock_status_reason text
  )
  WHERE x.panel_name IS NOT NULL AND x.panel_name <> ''
    AND x.link_code IS NOT NULL AND x.link_code <> '';

  SELECT COUNT(*)::int, COUNT(DISTINCT panel_name)::int
  INTO v_entries_count, v_panels_count
  FROM _tick_incoming;

  -- Deterministic counts (avoid relying on ROW_COUNT across multi-step statements)
  SELECT COUNT(*)::int
  INTO v_presence_upserted
  FROM (SELECT 1 FROM _tick_incoming GROUP BY surface_name, panel_name, link_code) q;

  -- 0) Persistent link state (first/last seen per target)
  WITH seen AS (
    SELECT link_code, MAX(link_code_type) AS link_code_type
    FROM _tick_incoming
    GROUP BY link_code
  )
  INSERT INTO public.discovery_exposure_link_state (
    target_id, link_code, link_code_type, first_seen_at, last_seen_at
  )
  SELECT p_target_id, s.link_code, s.link_code_type, p_tick_ts, p_tick_ts
  FROM seen s
  ON CONFLICT (target_id, link_code)
  DO UPDATE SET
    link_code_type = EXCLUDED.link_code_type,
    last_seen_at = EXCLUDED.last_seen_at;
  GET DIAGNOSTICS v_link_state_upserted = ROW_COUNT;

  -- 1) Raw insert
  INSERT INTO public.discovery_exposure_entries_raw (
    tick_id, target_id, ts,
    surface_name, panel_name, panel_display_name, panel_type, feature_tags,
    page_index, rank, link_code, link_code_type,
    global_ccu, is_visible, lock_status, lock_status_reason
  )
  SELECT
    p_tick_id, p_target_id, p_tick_ts,
    i.surface_name, i.panel_name, i.panel_display_name, i.panel_type, i.feature_tags,
    i.page_index, i.rank, i.link_code, i.link_code_type,
    i.global_ccu, i.is_visible, i.lock_status, i.lock_status_reason
  FROM _tick_incoming i;
  GET DIAGNOSTICS v_raw_inserted = ROW_COUNT;

  -- 2) Presence segments (+ enter events)
  WITH incoming_presence AS (
    SELECT
      surface_name, panel_name,
      MAX(panel_display_name) AS panel_display_name,
      MAX(panel_type) AS panel_type,
      MAX(feature_tags) AS feature_tags,
      link_code,
      MAX(link_code_type) AS link_code_type,
      MIN(rank)::int AS rank,
      MAX(global_ccu)::int AS global_ccu
    FROM _tick_incoming
    GROUP BY surface_name, panel_name, link_code
  ),
  upserted AS (
    INSERT INTO public.discovery_exposure_presence_segments (
      target_id, surface_name, panel_name, panel_display_name, panel_type, feature_tags,
      link_code, link_code_type,
      start_ts, last_seen_ts, end_ts,
      best_rank, rank_sum, rank_samples, end_rank,
      ccu_start, ccu_max, ccu_end, closed_reason
    )
    SELECT
      p_target_id, i.surface_name, i.panel_name, i.panel_display_name, i.panel_type, i.feature_tags,
      i.link_code, i.link_code_type,
      p_tick_ts, p_tick_ts, NULL,
      i.rank, i.rank, 1, i.rank,
      i.global_ccu, i.global_ccu, i.global_ccu, NULL
    FROM incoming_presence i
    ON CONFLICT (target_id, panel_name, link_code) WHERE end_ts IS NULL
    DO UPDATE SET
      surface_name = EXCLUDED.surface_name,
      panel_display_name = EXCLUDED.panel_display_name,
      panel_type = EXCLUDED.panel_type,
      feature_tags = EXCLUDED.feature_tags,
      last_seen_ts = p_tick_ts,
      best_rank = LEAST(COALESCE(discovery_exposure_presence_segments.best_rank, EXCLUDED.best_rank), EXCLUDED.best_rank),
      rank_sum = discovery_exposure_presence_segments.rank_sum + EXCLUDED.rank_sum,
      rank_samples = discovery_exposure_presence_segments.rank_samples + 1,
      end_rank = EXCLUDED.end_rank,
      ccu_end = EXCLUDED.ccu_end,
      ccu_max = CASE
        WHEN discovery_exposure_presence_segments.ccu_max IS NULL THEN EXCLUDED.ccu_max
        WHEN EXCLUDED.ccu_max IS NULL THEN discovery_exposure_presence_segments.ccu_max
        ELSE GREATEST(discovery_exposure_presence_segments.ccu_max, EXCLUDED.ccu_max)
      END,
      closed_reason = NULL
    RETURNING
      (xmax = 0) AS inserted,
      surface_name, panel_name, panel_display_name, panel_type, feature_tags,
      link_code, link_code_type, end_rank, ccu_end
  )
  INSERT INTO public.discovery_exposure_presence_events (
    target_id, tick_id, ts, event_type,
    surface_name, panel_name, panel_display_name, panel_type, feature_tags,
    link_code, link_code_type, rank, global_ccu
  )
  SELECT
    p_target_id, p_tick_id, p_tick_ts, 'enter',
    u.surface_name, u.panel_name, u.panel_display_name, u.panel_type, u.feature_tags,
    u.link_code, u.link_code_type, u.end_rank, u.ccu_end
  FROM upserted u
  WHERE u.inserted;
  GET DIAGNOSTICS v_events_entered = ROW_COUNT;

  -- Close presence segments not seen (+ exit events)
  CREATE TEMP TABLE _presence_closed ON COMMIT DROP AS
  WITH closed AS (
    UPDATE public.discovery_exposure_presence_segments s
    SET end_ts = s.last_seen_ts, closed_reason = 'absent_confirmed'
    WHERE s.target_id = p_target_id AND s.end_ts IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM _tick_incoming k
        WHERE k.panel_name = s.panel_name AND k.link_code = s.link_code
      )
    RETURNING
      s.surface_name, s.panel_name, s.panel_display_name, s.panel_type, s.feature_tags,
      s.link_code, s.link_code_type, s.end_rank, s.ccu_end, s.last_seen_ts, s.closed_reason
  )
  SELECT * FROM closed;

  SELECT COUNT(*)::int INTO v_presence_closed FROM _presence_closed;

  INSERT INTO public.discovery_exposure_presence_events (
    target_id, tick_id, ts, event_type,
    surface_name, panel_name, panel_display_name, panel_type, feature_tags,
    link_code, link_code_type, rank, global_ccu, closed_reason
  )
  SELECT
    p_target_id, p_tick_id, c.last_seen_ts, 'exit',
    c.surface_name, c.panel_name, c.panel_display_name, c.panel_type, c.feature_tags,
    c.link_code, c.link_code_type, c.end_rank, c.ccu_end, c.closed_reason
  FROM _presence_closed c;
  GET DIAGNOSTICS v_events_exited = ROW_COUNT;

  -- 3) Rank segments - close replaced first
  UPDATE public.discovery_exposure_rank_segments s
  SET end_ts = s.last_seen_ts, closed_reason = 'replaced'
  WHERE s.target_id = p_target_id AND s.end_ts IS NULL
    AND EXISTS (
      SELECT 1 FROM _tick_incoming k
      WHERE k.panel_name = s.panel_name AND k.rank = s.rank AND k.link_code <> s.link_code
    );
  GET DIAGNOSTICS v_rank_replaced_closed = ROW_COUNT;

  WITH incoming_rank AS (
    SELECT surface_name, panel_name, MAX(panel_display_name) AS panel_display_name,
      MAX(panel_type) AS panel_type, MAX(feature_tags) AS feature_tags,
      rank, link_code, MAX(link_code_type) AS link_code_type, MAX(global_ccu)::int AS global_ccu
    FROM _tick_incoming GROUP BY surface_name, panel_name, rank, link_code
  )
  INSERT INTO public.discovery_exposure_rank_segments (
    target_id, surface_name, panel_name, panel_display_name, panel_type, feature_tags,
    rank, link_code, link_code_type,
    start_ts, last_seen_ts, end_ts,
    ccu_start, ccu_max, ccu_end, closed_reason
  )
  SELECT
    p_target_id, i.surface_name, i.panel_name, i.panel_display_name, i.panel_type, i.feature_tags,
    i.rank, i.link_code, i.link_code_type,
    p_tick_ts, p_tick_ts, NULL,
    i.global_ccu, i.global_ccu, i.global_ccu, NULL
  FROM incoming_rank i
  ON CONFLICT (target_id, panel_name, rank) WHERE end_ts IS NULL
  DO UPDATE SET
    surface_name = EXCLUDED.surface_name,
    panel_display_name = EXCLUDED.panel_display_name,
    panel_type = EXCLUDED.panel_type,
    feature_tags = EXCLUDED.feature_tags,
    last_seen_ts = p_tick_ts,
    ccu_end = EXCLUDED.ccu_end,
    ccu_max = CASE
      WHEN discovery_exposure_rank_segments.ccu_max IS NULL THEN EXCLUDED.ccu_max
      WHEN EXCLUDED.ccu_max IS NULL THEN discovery_exposure_rank_segments.ccu_max
      ELSE GREATEST(discovery_exposure_rank_segments.ccu_max, EXCLUDED.ccu_max)
    END,
    closed_reason = NULL;
  GET DIAGNOSTICS v_rank_upserted = ROW_COUNT;

  -- Close absent ranks
  UPDATE public.discovery_exposure_rank_segments s
  SET end_ts = s.last_seen_ts, closed_reason = 'absent_confirmed'
  WHERE s.target_id = p_target_id AND s.end_ts IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM _tick_incoming k
      WHERE k.panel_name = s.panel_name AND k.rank = s.rank
    );
  GET DIAGNOSTICS v_rank_absent_closed = ROW_COUNT;

  -- 4) Tick telemetry update
  UPDATE public.discovery_exposure_ticks
  SET ts_end = now(), status = 'ok',
      branch = p_branch, test_variant_name = p_test_variant_name,
      test_name = p_test_name, test_analytics_id = p_test_analytics_id,
      panels_count = COALESCE(v_panels_count, 0),
      entries_count = COALESCE(v_entries_count, 0),
      duration_ms = p_duration_ms, correlation_id = p_correlation_id
  WHERE id = p_tick_id AND target_id = p_target_id;

  RETURN jsonb_build_object(
    'tick_id', p_tick_id, 'target_id', p_target_id,
    'panels_count', COALESCE(v_panels_count, 0), 'entries_count', COALESCE(v_entries_count, 0),
    'raw_inserted', v_raw_inserted,
    'presence_upserted', v_presence_upserted, 'presence_closed', v_presence_closed,
    'rank_replaced_closed', v_rank_replaced_closed, 'rank_upserted', v_rank_upserted,
    'rank_absent_closed', v_rank_absent_closed,
    'events_entered', v_events_entered, 'events_exited', v_events_exited,
    'link_state_upserted', v_link_state_upserted
  );
END;
$$;
