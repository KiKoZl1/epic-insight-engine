-- Fix search_path linter warning on normalize_island_title_for_dup
CREATE OR REPLACE FUNCTION public.normalize_island_title_for_dup(p_title text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  SELECT lower(regexp_replace(
    regexp_replace(COALESCE(p_title, ''), '[^a-zA-Z0-9 ]', '', 'g'),
    '\s+', ' ', 'g'
  ));
$function$;