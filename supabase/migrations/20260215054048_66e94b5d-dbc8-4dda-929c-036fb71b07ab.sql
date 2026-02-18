-- Idempotent cron setup for discover-collector (project-agnostic)
DO $$
DECLARE
  v_url text := current_setting('app.settings.supabase_url', true);
  v_key text := current_setting('app.settings.service_role_key', true);
  v_jobid bigint;
BEGIN
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE 'Skipping cron setup: missing app.settings.supabase_url/service_role_key';
    RETURN;
  END IF;

  -- Orchestrate every minute
  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-collector-orchestrate-minute'
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule(v_jobid);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not unschedule discover-collector-orchestrate-minute: %', SQLERRM;
    END;
  END IF;

  PERFORM cron.schedule(
    'discover-collector-orchestrate-minute',
    '* * * * *',
    format($job$
      SELECT net.http_post(
        url := %L || '/functions/v1/discover-collector',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body := '{"mode":"orchestrate"}'::jsonb
      ) AS request_id;
    $job$, v_url, v_key)
  );

  -- Weekly kickoff
  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-collector-weekly-v2'
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule(v_jobid);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not unschedule discover-collector-weekly-v2: %', SQLERRM;
    END;
  END IF;

  PERFORM cron.schedule(
    'discover-collector-weekly-v2',
    '0 6 * * 1',
    format($job$
      SELECT net.http_post(
        url := %L || '/functions/v1/discover-collector',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body := '{"mode":"start"}'::jsonb
      ) AS request_id;
    $job$, v_url, v_key)
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping cron migration due to error: %', SQLERRM;
END $$;
