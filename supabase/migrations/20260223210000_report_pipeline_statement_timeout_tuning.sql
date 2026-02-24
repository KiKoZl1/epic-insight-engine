-- Keep full-data rebuild stable by increasing statement_timeout only on heavy report/exposure RPCs.
-- No fallback/partial behavior: this migration gives SQL more headroom to finish.

DO $$
DECLARE
  rec record;
  v_timeout text := '120s';
BEGIN
  FOR rec IN
    SELECT
      n.nspname AS schema_name,
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS identity_args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'report_finalize_kpis',
        'report_finalize_rankings',
        'report_finalize_creators',
        'report_finalize_categories',
        'report_finalize_distributions',
        'report_finalize_trending',
        'report_finalize_wow_movers',
        'report_finalize_tool_split',
        'report_finalize_rookies',
        'report_finalize_exposure_analysis',
        'report_finalize_exposure_efficiency',
        'report_finalize_category_movers',
        'report_finalize_creator_movers',
        'report_link_metadata_coverage',
        'report_low_perf_histogram',
        'report_exposure_coverage',
        'report_new_islands_by_launch',
        'report_new_islands_by_launch_count',
        'report_most_updated_islands',
        'discovery_exposure_top_by_panel',
        'discovery_exposure_panel_daily_summaries',
        'discovery_exposure_top_panels',
        'discovery_exposure_breadth_top'
      )
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %I.%I(%s) SET statement_timeout = %L',
      rec.schema_name,
      rec.function_name,
      rec.identity_args,
      v_timeout
    );
  END LOOP;
END $$;

