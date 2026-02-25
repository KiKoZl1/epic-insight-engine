-- Remove deprecated AI cache table (replaced by discover_lookup_ai_recent + discover_lookup_recent)

DROP TABLE IF EXISTS public.discover_lookup_ai_cache;
