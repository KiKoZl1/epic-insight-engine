
CREATE OR REPLACE FUNCTION public.enqueue_discover_link_metadata(p_link_codes text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count INT := 0;
BEGIN
  INSERT INTO public.discover_link_metadata (link_code, link_code_type, next_due_at)
  SELECT
    lc,
    CASE WHEN lc ~ '^\d{4}-\d{4}-\d{4}$' THEN 'island' ELSE 'collection' END,
    now()
  FROM unnest(p_link_codes) AS lc
  ON CONFLICT (link_code) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;
