DO $$
DECLARE
  v_url text := current_setting('app.settings.supabase_url', true);
  v_key text := current_setting('app.settings.service_role_key', true);
  v_jobid bigint;
BEGIN
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE 'Skipping island-page cache cron setup: missing app.settings.supabase_url/service_role_key';
    RETURN;
  END IF;

  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-island-page-cache-refresh-5min'
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule(v_jobid);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not unschedule discover-island-page-cache-refresh-5min: %', SQLERRM;
    END;
  END IF;

  PERFORM cron.schedule(
    'discover-island-page-cache-refresh-5min',
    '*/5 * * * *',
    format($job$
      SELECT net.http_post(
        url := %L || '/functions/v1/discover-island-page',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L,
          'apikey', %L
        ),
        body := '{"mode":"refresh_cache","batchSize":50}'::jsonb
      ) AS request_id;
    $job$, v_url, v_key, v_key)
  );

  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-island-page-cache-cleanup-hourly'
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule(v_jobid);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not unschedule discover-island-page-cache-cleanup-hourly: %', SQLERRM;
    END;
  END IF;

  PERFORM cron.schedule(
    'discover-island-page-cache-cleanup-hourly',
    '0 * * * *',
    $job$
      DELETE FROM public.discover_island_page_cache
      WHERE last_accessed_at < now() - interval '3 days';
    $job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping island-page cache cron migration due to error: %', SQLERRM;
END $$;
