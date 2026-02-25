-- Discover Live v2.1 config for fixed premium ordering and panel alias resolution

CREATE TABLE IF NOT EXISTS public.discovery_live_panel_config (
  panel_key TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  description TEXT NULL,
  display_order INT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT true,
  row_kind TEXT NOT NULL DEFAULT 'island' CHECK (row_kind IN ('island','collection','mixed')),
  is_premium BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS discovery_live_panel_config_order_idx
  ON public.discovery_live_panel_config (display_order, panel_key);

CREATE TABLE IF NOT EXISTS public.discovery_live_panel_alias (
  alias_token TEXT PRIMARY KEY,
  target_panel_name TEXT NOT NULL,
  resolver_hint TEXT NULL,
  priority INT NOT NULL DEFAULT 100,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS discovery_live_panel_alias_priority_idx
  ON public.discovery_live_panel_alias (priority, alias_token);

ALTER TABLE public.discovery_live_panel_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_live_panel_alias ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_live_panel_config'
      AND policyname='select_discovery_live_panel_config_public'
  ) THEN
    CREATE POLICY select_discovery_live_panel_config_public
      ON public.discovery_live_panel_config FOR SELECT
      TO public
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_live_panel_config'
      AND policyname='all_discovery_live_panel_config_service_role'
  ) THEN
    CREATE POLICY all_discovery_live_panel_config_service_role
      ON public.discovery_live_panel_config FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_live_panel_alias'
      AND policyname='select_discovery_live_panel_alias_public'
  ) THEN
    CREATE POLICY select_discovery_live_panel_alias_public
      ON public.discovery_live_panel_alias FOR SELECT
      TO public
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='discovery_live_panel_alias'
      AND policyname='all_discovery_live_panel_alias_service_role'
  ) THEN
    CREATE POLICY all_discovery_live_panel_alias_service_role
      ON public.discovery_live_panel_alias FOR ALL
      TO public
      USING ((auth.jwt() ->> 'role') = 'service_role')
      WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');
  END IF;
END $$;

INSERT INTO public.discovery_live_panel_config (panel_key, label, description, display_order, enabled, row_kind, is_premium)
VALUES
  ('homebar', 'Homebar', 'Top live maps in Discovery right now.', 10, true, 'mixed', true),
  ('trending_variety', 'Trending Variety', 'Most played and fastest-rising maps in Variety.', 20, true, 'island', true),
  ('epics_picks', 'Epic''s Picks', 'Curated maps hand-picked by Epic.', 30, true, 'island', true),
  ('game_collections', 'Game Collections', 'IP collections and branded experiences.', 40, true, 'collection', true),
  ('battle_royales_by_epic', 'Battle Royales by Epic', 'Official Battle Royale experiences by Epic.', 50, true, 'island', true),
  ('sponsored', 'Sponsored', 'Promoted placements paid by developers.', 60, true, 'island', true),
  ('popular', 'Popular', 'Currently popular maps with strong live player demand.', 70, true, 'island', true),
  ('fan_favorites', 'Fan Favorites', 'Highly replayed and community-favorite combat maps.', 80, true, 'island', true),
  ('most_engaging', 'Most Engaging', 'Maps with deep engagement and replay behavior.', 90, true, 'island', true),
  ('new', 'New', 'Recently released maps gaining traction.', 100, true, 'island', true),
  ('updated', 'Updated', 'Recently updated maps with renewed activity.', 110, true, 'island', true)
ON CONFLICT (panel_key) DO UPDATE
SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  display_order = EXCLUDED.display_order,
  enabled = EXCLUDED.enabled,
  row_kind = EXCLUDED.row_kind,
  is_premium = EXCLUDED.is_premium,
  updated_at = now();

INSERT INTO public.discovery_live_panel_alias (alias_token, target_panel_name, resolver_hint, priority)
VALUES
  ('reference_current_island', 'Homebar_Default', 'rank:1', 1),
  ('reference_nestedrecentlyplayed_2', 'Nested_RecentlyPlayed', 'rank:2', 10),
  ('reference_nestedtrendingindiscover_1', 'Nested_TrendingInDiscover', 'rank:1', 5),
  ('ref_panel_test_epicspickshomebar_1', 'Nested_EpicsPicks', 'rank:1', 2),
  ('ref_panel_updatefeeder_3', 'UpdatedIslandsFromCreators', 'rank:3', 20),
  ('ref_panel_newfeeder_2', 'NewAndUpdated1', 'rank:2', 15)
ON CONFLICT (alias_token) DO UPDATE
SET
  target_panel_name = EXCLUDED.target_panel_name,
  resolver_hint = EXCLUDED.resolver_hint,
  priority = EXCLUDED.priority,
  updated_at = now();
