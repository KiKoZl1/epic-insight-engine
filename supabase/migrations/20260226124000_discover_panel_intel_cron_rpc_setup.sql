CREATE OR REPLACE FUNCTION public.setup_discover_panel_intel_refresh_cron(
  p_url text,
  p_service_role_key text,
  p_schedule text DEFAULT '*/10 * * * *',
  p_surface_name text DEFAULT 'CreativeDiscoverySurface_Frontend',
  p_window_days int DEFAULT 14,
  p_batch_targets int DEFAULT 16
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jobid bigint;
  v_schedule text := COALESCE(NULLIF(p_schedule, ''), '*/10 * * * *');
  v_window_days int := GREATEST(1, LEAST(COALESCE(p_window_days, 14), 60));
  v_batch_targets int := GREATEST(1, LEAST(COALESCE(p_batch_targets, 16), 64));
BEGIN
  IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_url IS NULL OR p_url = '' OR p_service_role_key IS NULL OR p_service_role_key = '' THEN
    RAISE EXCEPTION 'missing_url_or_key';
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
    v_schedule,
    format($job$
      SELECT net.http_post(
        url := %L || '/functions/v1/discover-panel-intel-refresh',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L,
          'apikey', %L
        ),
        body := %L::jsonb
      ) AS request_id;
    $job$,
      p_url,
      p_service_role_key,
      p_service_role_key,
      json_build_object(
        'surfaceName', COALESCE(NULLIF(p_surface_name, ''), 'CreativeDiscoverySurface_Frontend'),
        'windowDays', v_window_days,
        'batchTargets', v_batch_targets,
        'regions', json_build_array('NAE', 'EU', 'BR', 'ASIA')
      )::text
    )
  );

  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'discover-panel-intel-refresh-10min'
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'job_name', 'discover-panel-intel-refresh-10min',
    'job_id', v_jobid,
    'schedule', v_schedule,
    'surface_name', COALESCE(NULLIF(p_surface_name, ''), 'CreativeDiscoverySurface_Frontend'),
    'window_days', v_window_days,
    'batch_targets', v_batch_targets
  );
END;
$$;
