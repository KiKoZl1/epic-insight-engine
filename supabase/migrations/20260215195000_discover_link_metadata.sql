-- Links Service metadata cache for islands + collections (playlist_*, reference_*, ref_panel_*, etc.)
-- Canonical source for title/thumbnail and other card metadata (see docs/LINKS_SERVICE_MNEMONIC_INFO.md).

CREATE TABLE IF NOT EXISTS public.discover_link_metadata (
  link_code TEXT PRIMARY KEY,
  link_code_type TEXT NOT NULL CHECK (link_code_type IN ('island','collection')),
  namespace TEXT NULL,
  link_type TEXT NULL,
  account_id TEXT NULL,
  creator_name TEXT NULL,
  support_code TEXT NULL,
  title TEXT NULL,
  tagline TEXT NULL,
  introduction TEXT NULL,
  locale TEXT NULL,
  image_url TEXT NULL,
  image_urls JSONB NULL,
  extra_image_urls JSONB NULL,
  video_vuid TEXT NULL,
  max_players INT NULL,
  min_players INT NULL,
  max_social_party_size INT NULL,
  ratings JSONB NULL,
  version INT NULL,
  created_at_epic TIMESTAMPTZ NULL,
  published_at_epic TIMESTAMPTZ NULL,
  updated_at_epic TIMESTAMPTZ NULL,
  last_activated_at_epic TIMESTAMPTZ NULL,
  moderation_status TEXT NULL,
  link_state TEXT NULL,
  discovery_intent TEXT NULL,
  active BOOLEAN NULL,
  disabled BOOLEAN NULL,
  -- Ops
  last_fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(), -- last fetch attempt time
  next_due_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error TEXT NULL,
  locked_at TIMESTAMPTZ NULL,
  lock_id UUID NULL,
  raw JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS discover_link_metadata_next_due_idx
  ON public.discover_link_metadata (next_due_at);

CREATE INDEX IF NOT EXISTS discover_link_metadata_updated_at_epic_idx
  ON public.discover_link_metadata (updated_at_epic DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS discover_link_metadata_support_code_idx
  ON public.discover_link_metadata (support_code);

CREATE INDEX IF NOT EXISTS discover_link_metadata_image_url_idx
  ON public.discover_link_metadata (image_url);

CREATE INDEX IF NOT EXISTS discover_link_metadata_locked_at_idx
  ON public.discover_link_metadata (locked_at);

ALTER TABLE public.discover_link_metadata ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discover_link_metadata'
      AND policyname='select_discover_link_metadata_authenticated'
  ) THEN
    CREATE POLICY select_discover_link_metadata_authenticated
      ON public.discover_link_metadata FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discover_link_metadata'
      AND policyname='all_discover_link_metadata_service_role'
  ) THEN
    CREATE POLICY all_discover_link_metadata_service_role
      ON public.discover_link_metadata FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;
END $$;

-- Change events (thumb/title/updated/moderation transitions)
CREATE TABLE IF NOT EXISTS public.discover_link_metadata_events (
  id BIGSERIAL PRIMARY KEY,
  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  link_code TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('thumb_changed','title_changed','epic_updated','moderation_changed')),
  old_value JSONB NULL,
  new_value JSONB NULL
);

CREATE INDEX IF NOT EXISTS discover_link_metadata_events_link_ts_idx
  ON public.discover_link_metadata_events (link_code, ts DESC);

ALTER TABLE public.discover_link_metadata_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discover_link_metadata_events'
      AND policyname='select_discover_link_metadata_events_authenticated'
  ) THEN
    CREATE POLICY select_discover_link_metadata_events_authenticated
      ON public.discover_link_metadata_events FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discover_link_metadata_events'
      AND policyname='all_discover_link_metadata_events_service_role'
  ) THEN
    CREATE POLICY all_discover_link_metadata_events_service_role
      ON public.discover_link_metadata_events FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;
END $$;

-- Enqueue link codes (insert stubs if missing; bump next_due_at for existing)
CREATE OR REPLACE FUNCTION public.enqueue_discover_link_metadata(
  p_link_codes TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INT := 0;
  v_updated INT := 0;
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  WITH input AS (
    SELECT DISTINCT trim(x) AS link_code
    FROM unnest(COALESCE(p_link_codes, '{}'::text[])) AS x
    WHERE x IS NOT NULL AND trim(x) <> ''
  ),
  ins AS (
    INSERT INTO public.discover_link_metadata (link_code, link_code_type, next_due_at)
    SELECT
      i.link_code,
      CASE WHEN i.link_code ~ '^[0-9]{4}-[0-9]{4}-[0-9]{4}$' THEN 'island' ELSE 'collection' END,
      now()
    FROM input i
    ON CONFLICT (link_code) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_inserted FROM ins;

  UPDATE public.discover_link_metadata m
  SET next_due_at = LEAST(m.next_due_at, now()),
      updated_at = now()
  WHERE m.link_code = ANY(COALESCE(p_link_codes, '{}'::text[]));
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$;

-- Claim due items with a lightweight logical lock (for orchestrator runs)
CREATE OR REPLACE FUNCTION public.claim_discover_link_metadata(
  p_take INT DEFAULT 100,
  p_stale_after_seconds INT DEFAULT 180
)
RETURNS TABLE (
  link_code TEXT,
  lock_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH due AS (
    SELECT m.link_code
    FROM public.discover_link_metadata m
    WHERE m.next_due_at <= now()
      AND (
        m.locked_at IS NULL OR
        m.locked_at < now() - make_interval(secs => GREATEST(p_stale_after_seconds, 1))
      )
    ORDER BY m.next_due_at ASC
    LIMIT GREATEST(p_take, 1)
  ),
  upd AS (
    UPDATE public.discover_link_metadata m
    SET locked_at = now(),
        lock_id = gen_random_uuid(),
        updated_at = now()
    FROM due d
    WHERE m.link_code = d.link_code
    RETURNING m.link_code, m.lock_id
  )
  SELECT u.link_code, u.lock_id FROM upd u;
END;
$$;

