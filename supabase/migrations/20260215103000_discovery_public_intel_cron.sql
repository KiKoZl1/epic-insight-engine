-- Refresh public "Discovery Intelligence" snapshots frequently.
-- This uses pg_net to call the edge function (service_role), which then calls the RPC.

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'discover-exposure-intel-refresh-5min'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'discover-exposure-intel-refresh-5min',
    '*/5 * * * *',
    $job$
      SELECT
        net.http_post(
          url := current_setting('app.settings.supabase_url') || '/functions/v1/discover-exposure-collector',
          headers := '{"Content-Type":"application/json"}'::jsonb,
          body := '{"mode":"intel_refresh"}'::jsonb
        );
    $job$
  );
END
$$;

