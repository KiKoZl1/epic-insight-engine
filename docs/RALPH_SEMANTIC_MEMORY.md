# Ralph Semantic Memory

This layer upgrades Ralph from operational memory only to hybrid semantic retrieval.

## Components

- `public.ralph_memory_documents`
  - chunked project/domain documents with optional embeddings.
- `public.search_ralph_memory_documents(...)`
  - hybrid scoring:
    - vector similarity (80%)
    - full-text rank (20%)
- `public.get_ralph_semantic_context(...)`
  - JSON wrapper around semantic matches.

## Ingest memory

Dry run (scan/chunk only):

```powershell
npm run ralph:memory:ingest -- --paths=docs,src/pages --dry-run=true
```

Real ingest with embeddings:

```powershell
npm run ralph:memory:ingest -- --paths=docs,src/pages,src/components --scope=project,product,discover --use-embeddings=true --embedding-provider=nvidia --embedding-model=nvidia/nv-embedqa-e5-v5
```

Notes:
- Requires `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.
- Embeddings with NVIDIA require `NVIDIA_API_KEY`.
- Current runner has text-search fallback when vector search fails (dimension/provider mismatch).

## Query memory

```powershell
npm run ralph:memory:query -- --query="how to improve csv tool reliability and UX" --scope=project,product --match-count=8
```

## Runner integration

`scripts/ralph_local_runner.mjs` now retrieves semantic matches before each run and injects them into prompts.

Extra flags:

- `--semantic-match-count=8`
- `--semantic-min-importance=40`
- `--semantic-use-embeddings=true`
- `--semantic-embedding-provider=nvidia`
- `--semantic-embedding-model=nvidia/nv-embedqa-e5-v5`

## Validation SQL

```sql
select count(*) as docs from public.ralph_memory_documents where is_active = true;
select * from public.search_ralph_memory_documents(
  p_query_text => 'exposure stale targets and metadata backlog',
  p_query_embedding_text => null,
  p_scope => array['project','discover'],
  p_match_count => 10,
  p_min_importance => 0
);
```
