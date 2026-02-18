-- Admin RPCs to manage discover cron jobs without direct privileges on cron.job

CREATE OR REPLACE FUNCTION public._assert_discover_cron_admin_access()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN
    RETURN;
  END IF;

  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = auth.uid()
      AND ur.role IN ('admin'::public.app_role, 'editor'::public.app_role)
  ) THEN
    RETURN;
  END IF;

  RAISE EXCEPTION
    USING ERRCODE = '42501', MESSAGE = 'forbidden: admin/editor or service_role required';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_discover_crons()
RETURNS TABLE (
  jobid bigint,
  jobname text,
  schedule text,
  active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._assert_discover_cron_admin_access();

  RETURN QUERY
  SELECT j.jobid, j.jobname, j.schedule, j.active
  FROM cron.job j
  WHERE j.jobname LIKE 'discover-%'
  ORDER BY j.jobname;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_discover_cron_active(
  p_jobname text,
  p_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jobid bigint;
  v_updated integer := 0;
BEGIN
  PERFORM public._assert_discover_cron_admin_access();

  IF p_jobname IS NULL OR p_jobname = '' OR p_jobname NOT LIKE 'discover-%' THEN
    RAISE EXCEPTION
      USING ERRCODE = '22023', MESSAGE = 'jobname must start with discover-';
  END IF;

  SELECT j.jobid
  INTO v_jobid
  FROM cron.job j
  WHERE j.jobname = p_jobname
  LIMIT 1;

  IF v_jobid IS NOT NULL THEN
    PERFORM cron.alter_job(v_jobid, NULL, NULL, NULL, NULL, COALESCE(p_active, false));
    v_updated := 1;
  END IF;

  RETURN jsonb_build_object(
    'jobname', p_jobname,
    'active', COALESCE(p_active, false),
    'updated', v_updated
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_pause_discover_crons()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_updated integer := 0;
BEGIN
  PERFORM public._assert_discover_cron_admin_access();

  FOR r IN
    SELECT j.jobid
    FROM cron.job j
    WHERE j.jobname LIKE 'discover-%'
      AND j.active = true
  LOOP
    PERFORM cron.alter_job(r.jobid, NULL, NULL, NULL, NULL, false);
    v_updated := v_updated + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'action', 'pause',
    'updated', v_updated
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resume_discover_crons()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_updated integer := 0;
BEGIN
  PERFORM public._assert_discover_cron_admin_access();

  FOR r IN
    SELECT j.jobid
    FROM cron.job j
    WHERE j.jobname LIKE 'discover-%'
      AND j.active = false
  LOOP
    PERFORM cron.alter_job(r.jobid, NULL, NULL, NULL, NULL, true);
    v_updated := v_updated + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'action', 'resume',
    'updated', v_updated
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_recent_discover_cron_runs(
  p_minutes integer DEFAULT 60,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  jobname text,
  status text,
  start_time timestamptz,
  end_time timestamptz,
  return_message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_minutes integer := GREATEST(COALESCE(p_minutes, 60), 1);
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  PERFORM public._assert_discover_cron_admin_access();

  RETURN QUERY
  SELECT
    j.jobname::text,
    d.status::text,
    d.start_time,
    d.end_time,
    d.return_message::text
  FROM cron.job_run_details d
  JOIN cron.job j ON j.jobid = d.jobid
  WHERE j.jobname LIKE 'discover-%'
    AND d.start_time > now() - make_interval(mins => v_minutes)
  ORDER BY d.start_time DESC
  LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public._assert_discover_cron_admin_access() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_discover_crons() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_discover_cron_active(text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_pause_discover_crons() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_resume_discover_crons() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_recent_discover_cron_runs(integer, integer) TO authenticated, service_role;
