-- Tune Homebar token alias resolution to raw Discovery rails (no synthetic pool fallback)
INSERT INTO public.discovery_live_panel_alias (alias_token, target_panel_name, resolver_hint, priority)
VALUES
  ('reference_nestedtrendingindiscover_1', 'Nested_PeopleLove', 'rank:12', 5),
  ('ref_panel_test_epicspickshomebar_1', 'Nested_EpicsPicks', 'rank:1', 2),
  ('ref_panel_updatefeeder_3', 'Nested_EpicsPicks', 'rank:4', 20),
  ('ref_panel_newfeeder_2', 'Nested_Popular', 'rank:1', 15),
  ('ref_panel_livefeeder_1', 'Nested_Popular', 'rank:3', 7),
  ('ref_panel_noviolatorfeeder__3', 'Nested_PeopleLove', 'rank:1', 8),
  ('ref_panel_byepicfeeder_1', 'Nested_PeopleLove', 'rank:2', 9),
  ('ref_panel_newislandsfromcreators_1', 'Nested_PeopleLove', 'rank:3', 10),
  ('reference_nested_popular_3', 'Nested_Popular', 'rank:9', 11),
  ('ref_panel_nested_peoplelove_3', 'Nested_Popular', 'rank:12', 12)
ON CONFLICT (alias_token) DO UPDATE
SET
  target_panel_name = EXCLUDED.target_panel_name,
  resolver_hint = EXCLUDED.resolver_hint,
  priority = EXCLUDED.priority,
  updated_at = now();
