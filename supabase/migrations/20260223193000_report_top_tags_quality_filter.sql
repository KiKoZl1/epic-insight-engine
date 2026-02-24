-- Improve topTags quality for report section 15:
-- - normalize noisy casing/punctuation
-- - drop generic/system terms
-- - require minimum frequency and creator diversity
CREATE OR REPLACE FUNCTION public.report_finalize_categories(p_report_id uuid, p_limit int DEFAULT 15)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      COALESCE(NULLIF(INITCAP(LOWER(category)), ''), 'Fortnite UGC') AS cat_name,
      COALESCE(tags, '[]'::jsonb) AS tags,
      COALESCE(NULLIF(LOWER(TRIM(creator_code)), ''), 'unknown') AS creator_code,
      COALESCE(week_plays, 0) AS week_plays,
      COALESCE(week_unique, 0) AS week_unique,
      COALESCE(week_minutes, 0) AS week_minutes,
      COALESCE(week_peak_ccu_max, 0) AS week_peak_ccu_max
    FROM discover_report_islands
    WHERE report_id = p_report_id
      AND status = 'reported'
  ),
  cat_agg AS (
    SELECT
      cat_name,
      SUM(week_plays)::bigint AS total_plays,
      SUM(week_unique)::bigint AS unique_players,
      SUM(week_minutes)::bigint AS minutes_played,
      MAX(week_peak_ccu_max)::int AS peak_ccu,
      COUNT(*)::int AS maps
    FROM base
    GROUP BY cat_name
  ),
  raw_tags AS (
    SELECT
      creator_code,
      LOWER(TRIM(REGEXP_REPLACE(tag_raw, '\s+', ' ', 'g'))) AS tag_norm
    FROM base b
    CROSS JOIN LATERAL jsonb_array_elements_text(b.tags) AS tag_raw
  ),
  clean_tags AS (
    SELECT
      creator_code,
      TRIM(REGEXP_REPLACE(tag_norm, '[^[:alnum:]\s\+\-#&]', '', 'g')) AS tag_norm
    FROM raw_tags
    WHERE tag_norm IS NOT NULL
      AND tag_norm <> ''
  ),
  filtered_tags AS (
    SELECT creator_code, tag_norm
    FROM clean_tags
    WHERE LENGTH(tag_norm) BETWEEN 3 AND 48
      AND tag_norm NOT IN (
        'fortnite', 'ugc', 'island', 'islands', 'map', 'maps',
        'game', 'games', 'mode', 'modes', 'creative', 'epic',
        'experience', 'experiences'
      )
      AND tag_norm !~* '(^|\\s)(fortnite|ugc)(\\s|$)'
      AND tag_norm <> 'none'
  ),
  tag_agg AS (
    SELECT
      INITCAP(tag_norm) AS tag,
      COUNT(*)::int AS cnt,
      COUNT(DISTINCT creator_code)::int AS creator_count
    FROM filtered_tags
    GROUP BY INITCAP(tag_norm)
    HAVING COUNT(*) >= 3
       AND COUNT(DISTINCT creator_code) >= 2
    ORDER BY cnt DESC, creator_count DESC, INITCAP(tag_norm) ASC
    LIMIT 20
  )
  SELECT jsonb_build_object(
    'categoryShare', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', cat_name,
        'title', cat_name,
        'category', cat_name,
        'totalPlays', total_plays,
        'uniquePlayers', unique_players,
        'maps', maps,
        'value', total_plays
      ) ORDER BY total_plays DESC), '[]'::jsonb)
      FROM (SELECT * FROM cat_agg ORDER BY total_plays DESC LIMIT p_limit) t
    ),
    'categoryPopularity', (
      SELECT COALESCE(jsonb_object_agg(cat_name, maps), '{}'::jsonb)
      FROM (SELECT * FROM cat_agg ORDER BY maps DESC LIMIT 10) t
    ),
    'topCategoriesByPlays', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', cat_name,
        'value', total_plays
      ) ORDER BY total_plays DESC), '[]'::jsonb)
      FROM (SELECT * FROM cat_agg ORDER BY total_plays DESC LIMIT p_limit) t
    ),
    'topTags', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', tag,
        'tag', tag,
        'value', cnt,
        'count', cnt,
        'creators', creator_count
      ) ORDER BY cnt DESC, creator_count DESC), '[]'::jsonb)
      FROM tag_agg
    )
  );
$$;
