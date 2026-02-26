DO $$
DECLARE
  v_url text := current_setting('app.settings.supabase_url', true);
  v_key text := current_setting('app.settings.service_role_key', true);
  v_jobid bigint;
BEGIN
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE 'Skipping panel-intel cron setup: missing app.settings.supabase_url/service_role_key';
    RETURN;
  END IF;

  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-panel-intel-refresh-10min'
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule(v_jobid);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not unschedule discover-panel-intel-refresh-10min: %', SQLERRM;
    END;
  END IF;

  PERFORM cron.schedule(
    'discover-panel-intel-refresh-10min',
    '*/10 * * * *',
    format($job$
      SELECT net.http_post(
        url := %L || '/functions/v1/discover-panel-intel-refresh',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L,
          'apikey', %L
        ),
        body := '{
          "surfaceName": "CreativeDiscoverySurface_Frontend",
          "windowDays": 14,
          "batchTargets": 16,
          "regions": ["NAE", "EU", "BR", "ASIA"]
        }'::jsonb
      ) AS request_id;
    $job$, v_url, v_key, v_key)
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping panel-intel cron migration due to error: %', SQLERRM;
END $$;
