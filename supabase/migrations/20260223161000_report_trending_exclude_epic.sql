-- Exclude Epic-authored islands from trending topic NLP so UGC trends are not polluted.

CREATE OR REPLACE FUNCTION public.report_finalize_trending(
  p_report_id uuid,
  p_min_islands int DEFAULT 5,
  p_limit int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '45s'
AS $fn$
DECLARE
  v_stopwords text[] := ARRAY[
    'the','a','an','and','or','of','in','on','at','to','for','is','it',
    'by','with','from','up','out','if','my','no','not','but','all','new',
    'your','you','me','we','us','so','do','be','am','are','was','get',
    'has','had','how','its','let','may','our','own','say','she','too',
    'use','way','who','did','got','old','see','now','man','day',
    'any','few','big','per','try','ask',
    'fortnite','map','island','game','mode','v2','v3','v4',
    'chapter','season','update','beta','alpha','test','pro','mega','ultra',
    'super','extreme','ultimate','best','top','epic','updated'
  ];
  v_result jsonb;
BEGIN
  WITH ri AS (
    SELECT island_code, title, creator_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg
    FROM discover_report_islands
    WHERE report_id = p_report_id AND status = 'reported'
      AND title IS NOT NULL AND title <> ''
      AND NOT (
        lower(coalesce(creator_code, '')) IN ('epic', 'epic games', 'epic labs', 'fortnite')
        OR lower(coalesce(creator_code, '')) LIKE '%epic%'
      )
  ),
  cleaned AS (
    SELECT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           regexp_split_to_array(
             lower(regexp_replace(regexp_replace(title, '[^a-zA-Z0-9\s-]', ' ', 'g'), '\s+', ' ', 'g')),
             '\s+'
           ) AS words
    FROM ri
  ),
  unigrams AS (
    SELECT DISTINCT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           word AS ngram
    FROM cleaned,
         LATERAL unnest(words) AS word
    WHERE length(word) >= 3 AND word <> ALL(v_stopwords)
  ),
  bigrams AS (
    SELECT DISTINCT island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg,
           words[i] || ' ' || words[i+1] AS ngram
    FROM cleaned,
         LATERAL generate_series(1, array_length(words, 1) - 1) AS i
    WHERE length(words[i]) >= 2 AND length(words[i+1]) >= 2
      AND words[i] <> ALL(v_stopwords) AND words[i+1] <> ALL(v_stopwords)
  ),
  all_ngrams AS (
    SELECT ngram, island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg FROM unigrams
    UNION ALL
    SELECT ngram, island_code, week_plays, week_unique, week_peak_ccu_max, week_d1_avg FROM bigrams
  ),
  agg AS (
    SELECT
      ngram,
      COUNT(DISTINCT island_code)::int AS islands,
      SUM(COALESCE(week_plays, 0))::bigint AS total_plays,
      SUM(COALESCE(week_unique, 0))::bigint AS total_players,
      MAX(COALESCE(week_peak_ccu_max, 0))::int AS peak_ccu,
      AVG(COALESCE(week_d1_avg, 0)) FILTER (WHERE COALESCE(week_d1_avg, 0) > 0) AS avg_d1
    FROM all_ngrams
    GROUP BY ngram
    HAVING COUNT(DISTINCT island_code) >= p_min_islands
  ),
  ranked AS (
    SELECT *,
      initcap(ngram) AS display_name
    FROM agg
    ORDER BY total_plays DESC
    LIMIT p_limit
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', display_name,
    'keyword', ngram,
    'islands', islands,
    'totalPlays', total_plays,
    'totalPlayers', total_players,
    'peakCCU', peak_ccu,
    'avgD1', ROUND(COALESCE(avg_d1, 0)::numeric, 4),
    'value', total_plays,
    'label', islands || ' islands · ' ||
      CASE WHEN total_plays >= 1000000 THEN ROUND(total_plays::numeric / 1000000, 1) || 'M'
           WHEN total_plays >= 1000 THEN ROUND(total_plays::numeric / 1000, 1) || 'K'
           ELSE total_plays::text END || ' plays'
  )), '[]'::jsonb) INTO v_result
  FROM ranked;

  RETURN jsonb_build_object('trendingTopics', v_result);
END;
$fn$;

