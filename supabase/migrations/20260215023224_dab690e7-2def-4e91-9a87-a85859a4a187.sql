
UPDATE public.discovery_exposure_targets SET interval_minutes = 5 WHERE surface_name = 'CreativeDiscoverySurface_Frontend';
UPDATE public.discovery_exposure_targets SET interval_minutes = 10 WHERE surface_name = 'CreativeDiscoverySurface_Browse';

CREATE TABLE IF NOT EXISTS public.discovery_exposure_link_state (
  target_id UUID NOT NULL REFERENCES public.discovery_exposure_targets(id) ON DELETE CASCADE,
  link_code TEXT NOT NULL,
  link_code_type TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (target_id, link_code)
);
CREATE INDEX IF NOT EXISTS discovery_exposure_link_state_last_seen_idx ON public.discovery_exposure_link_state (target_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS discovery_exposure_link_state_link_code_idx ON public.discovery_exposure_link_state (link_code, last_seen_at DESC);
ALTER TABLE public.discovery_exposure_link_state ENABLE ROW LEVEL SECURITY;

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
CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_target_ts_idx ON public.discovery_exposure_presence_events (target_id, ts DESC);
CREATE INDEX IF NOT EXISTS discovery_exposure_presence_events_link_ts_idx ON public.discovery_exposure_presence_events (link_code, ts DESC);
ALTER TABLE public.discovery_exposure_presence_events ENABLE ROW LEVEL SECURITY;
