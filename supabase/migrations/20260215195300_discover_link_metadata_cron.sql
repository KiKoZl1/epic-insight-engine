-- Schedule link metadata collector orchestrator (1/min).
-- This collector populates discover_link_metadata from Epic Links Service.

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'discover-links-metadata-orchestrate-minute'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'discover-links-metadata-orchestrate-minute',
    '* * * * *',
    $job$
      SELECT
        net.http_post(
          url := current_setting('app.settings.supabase_url') || '/functions/v1/discover-links-metadata-collector',
          headers := '{"Content-Type":"application/json"}'::jsonb,
          body := '{"mode":"orchestrate"}'::jsonb
        );
    $job$
  );
END
$$;

