-- Ralph semantic memory foundation
-- Adds document memory with hybrid retrieval (vector + full text).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.ralph_memory_documents (
  id BIGSERIAL PRIMARY KEY,
  doc_key TEXT NOT NULL UNIQUE,
  doc_type TEXT NOT NULL DEFAULT 'doc',
  scope TEXT[] NOT NULL DEFAULT '{}',
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  importance INT NOT NULL DEFAULT 50 CHECK (importance >= 0 AND importance <= 100),
  token_count INT NULL,
  source_path TEXT NULL,
  content_hash TEXT NULL,
  embedding VECTOR(1536) NULL,
  search_text TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('simple', COALESCE(title, '') || ' ' || COALESCE(content, ''))
  ) STORED,
  is_active BOOLEAN NOT NULL DEFAULT true,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ralph_memory_documents_active_scope_idx
  ON public.ralph_memory_documents (is_active, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS ralph_memory_documents_type_idx
  ON public.ralph_memory_documents (doc_type, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS ralph_memory_documents_importance_idx
  ON public.ralph_memory_documents (importance DESC, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS ralph_memory_documents_search_idx
  ON public.ralph_memory_documents
  USING GIN (search_text);

CREATE INDEX IF NOT EXISTS ralph_memory_documents_embedding_idx
  ON public.ralph_memory_documents
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

ALTER TABLE public.ralph_memory_documents ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname='public' AND tablename='ralph_memory_documents'
      AND policyname='select_ralph_memory_documents_admin_editor'
  ) THEN
    CREATE POLICY select_ralph_memory_documents_admin_editor
      ON public.ralph_memory_documents
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.user_roles ur
          WHERE ur.user_id = auth.uid()
            AND ur.role IN ('admin', 'editor')
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname='public' AND tablename='ralph_memory_documents'
      AND policyname='all_ralph_memory_documents_service_role'
  ) THEN
    CREATE POLICY all_ralph_memory_documents_service_role
      ON public.ralph_memory_documents
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.upsert_ralph_memory_document(
  p_doc_key TEXT,
  p_doc_type TEXT DEFAULT 'doc',
  p_scope TEXT[] DEFAULT '{}',
  p_title TEXT DEFAULT '',
  p_content TEXT DEFAULT '',
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_embedding_text TEXT DEFAULT NULL,
  p_source_path TEXT DEFAULT NULL,
  p_content_hash TEXT DEFAULT NULL,
  p_importance INT DEFAULT 50,
  p_token_count INT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id BIGINT;
  v_type TEXT;
  v_importance INT;
  v_embedding VECTOR(1536);
BEGIN
  IF COALESCE(NULLIF(trim(p_doc_key), ''), '') = '' THEN
    RAISE EXCEPTION 'p_doc_key is required';
  END IF;

  v_type := CASE
    WHEN p_doc_type IN ('doc', 'code', 'run', 'decision', 'incident', 'playbook') THEN p_doc_type
    ELSE 'doc'
  END;

  v_importance := LEAST(GREATEST(COALESCE(p_importance, 50), 0), 100);

  IF COALESCE(NULLIF(trim(p_embedding_text), ''), '') <> '' THEN
    v_embedding := trim(p_embedding_text)::vector(1536);
  ELSE
    v_embedding := NULL;
  END IF;

  INSERT INTO public.ralph_memory_documents (
    doc_key,
    doc_type,
    scope,
    title,
    content,
    metadata,
    importance,
    token_count,
    source_path,
    content_hash,
    embedding,
    is_active,
    first_seen_at,
    last_seen_at,
    updated_at
  )
  VALUES (
    p_doc_key,
    v_type,
    COALESCE(p_scope, '{}'),
    COALESCE(p_title, ''),
    COALESCE(p_content, ''),
    COALESCE(p_metadata, '{}'::jsonb),
    v_importance,
    p_token_count,
    p_source_path,
    p_content_hash,
    v_embedding,
    COALESCE(p_is_active, true),
    now(),
    now(),
    now()
  )
  ON CONFLICT (doc_key)
  DO UPDATE SET
    doc_type = EXCLUDED.doc_type,
    scope = EXCLUDED.scope,
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    metadata = EXCLUDED.metadata,
    importance = EXCLUDED.importance,
    token_count = EXCLUDED.token_count,
    source_path = EXCLUDED.source_path,
    content_hash = EXCLUDED.content_hash,
    embedding = COALESCE(EXCLUDED.embedding, public.ralph_memory_documents.embedding),
    is_active = EXCLUDED.is_active,
    last_seen_at = now(),
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_ralph_memory_documents(
  p_query_text TEXT DEFAULT NULL,
  p_query_embedding_text TEXT DEFAULT NULL,
  p_scope TEXT[] DEFAULT '{}',
  p_match_count INT DEFAULT 8,
  p_min_importance INT DEFAULT 0
)
RETURNS TABLE (
  id BIGINT,
  doc_key TEXT,
  doc_type TEXT,
  title TEXT,
  content_excerpt TEXT,
  metadata JSONB,
  importance INT,
  score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope TEXT[] := COALESCE(p_scope, '{}');
  v_match_count INT := LEAST(GREATEST(COALESCE(p_match_count, 8), 1), 50);
  v_min_importance INT := LEAST(GREATEST(COALESCE(p_min_importance, 0), 0), 100);
  v_embedding VECTOR(1536);
  v_query TEXT := NULLIF(trim(COALESCE(p_query_text, '')), '');
BEGIN
  IF COALESCE(NULLIF(trim(COALESCE(p_query_embedding_text, '')), ''), '') <> '' THEN
    v_embedding := trim(p_query_embedding_text)::vector(1536);
  ELSE
    v_embedding := NULL;
  END IF;

  RETURN QUERY
  WITH ranked AS (
    SELECT
      d.id,
      d.doc_key,
      d.doc_type,
      d.title,
      d.content,
      d.metadata,
      d.importance,
      CASE
        WHEN v_embedding IS NOT NULL AND d.embedding IS NOT NULL
          THEN (1 - (d.embedding <=> v_embedding))
        ELSE NULL
      END AS vec_score,
      CASE
        WHEN v_query IS NOT NULL AND v_query <> ''
          THEN ts_rank(d.search_text, websearch_to_tsquery('simple', v_query))
        ELSE 0
      END AS text_score
    FROM public.ralph_memory_documents d
    WHERE d.is_active = true
      AND d.importance >= v_min_importance
      AND (
        COALESCE(array_length(d.scope, 1), 0) = 0
        OR COALESCE(array_length(v_scope, 1), 0) = 0
        OR d.scope && v_scope
      )
  )
  SELECT
    r.id,
    r.doc_key,
    r.doc_type,
    r.title,
    LEFT(r.content, 500) AS content_excerpt,
    r.metadata,
    r.importance,
    ROUND((
      COALESCE(r.vec_score, 0) * 0.80 +
      COALESCE(r.text_score, 0) * 0.20
    )::numeric, 6) AS score
  FROM ranked r
  WHERE
    (v_embedding IS NULL AND (v_query IS NULL OR v_query = ''))
    OR r.vec_score IS NOT NULL
    OR r.text_score > 0
  ORDER BY score DESC, r.importance DESC, r.id DESC
  LIMIT v_match_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ralph_semantic_context(
  p_query_text TEXT DEFAULT NULL,
  p_query_embedding_text TEXT DEFAULT NULL,
  p_scope TEXT[] DEFAULT '{}',
  p_match_count INT DEFAULT 8
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'scope', COALESCE(p_scope, '{}'),
    'query_text', p_query_text,
    'matches', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'doc_key', s.doc_key,
          'doc_type', s.doc_type,
          'title', s.title,
          'content_excerpt', s.content_excerpt,
          'metadata', s.metadata,
          'importance', s.importance,
          'score', s.score
        )
      )
      FROM public.search_ralph_memory_documents(
        p_query_text => p_query_text,
        p_query_embedding_text => p_query_embedding_text,
        p_scope => p_scope,
        p_match_count => p_match_count,
        p_min_importance => 0
      ) s
    ), '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_ralph_memory_document(TEXT, TEXT, TEXT[], TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, INT, INT, BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_ralph_memory_documents(TEXT, TEXT, TEXT[], INT, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_ralph_semantic_context(TEXT, TEXT, TEXT[], INT) TO authenticated, service_role;
