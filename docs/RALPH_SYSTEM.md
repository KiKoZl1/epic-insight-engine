# Ralph System Documentation

Comprehensive system documentation for Ralph autonomous operations, run orchestration, memory, and admin observability.

This document is code-evidence driven and focuses on what is implemented in this repository.

## 1. Scope

Ralph in this repository is composed of:

- Local run orchestrator and loop scripts.
- Semantic memory ingest and query scripts.
- Database operational schema for runs/actions/evals/incidents.
- Database memory schema for snapshots, items, decisions, and semantic documents.
- Admin Center observability widgets that read Ralph runtime state.

Evidence:
- NPM scripts expose `ralph:*` commands. (source: package.json:18)
- Main runner script exists and is executable flow owner. (source: scripts/ralph_local_runner.mjs:39)
- Loop supervisor exists for repeated execution. (source: scripts/ralph_loop.ps1:1)
- Ralph operational tables and RPCs are defined in migration SQL. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:3)
- Ralph memory tables and semantic retrieval are defined in migration SQL. (source: supabase/migrations/20260218154000_ralph_memory_context.sql:7, supabase/migrations/20260218182000_ralph_semantic_memory.sql:6)
- Admin page consumes Ralph health and table telemetry. (source: src/pages/admin/AdminOverview.tsx:863)

## 2. Architecture

## 2.1 Runtime Layers

1. Orchestration layer (`scripts/ralph_local_runner.mjs`, `scripts/ralph_loop.ps1`).
2. Persistence layer (Postgres tables + RPCs for run and memory state).
3. Context and retrieval layer (`get_ralph_context_pack`, `search_ralph_memory_documents`).
4. Admin read-only visualization layer in `/admin`.

Evidence:
- Orchestrator creates run state and records action/eval events through RPC. (source: scripts/ralph_local_runner.mjs:1094)
- Context pack is loaded before LLM planning/execution. (source: scripts/ralph_local_runner.mjs:1202)
- Semantic retrieval is called before candidate file selection. (source: scripts/ralph_local_runner.mjs:1268)
- Admin consumes `get_ralph_health` and Ralph tables. (source: src/pages/admin/AdminOverview.tsx:878)

## 2.2 High-Level Data Flow

1. Operator invokes `npm run ralph:local` or `npm run ralph:loop`.
2. Runner validates config and computes guard decisions.
3. Runner starts DB run row (`start_ralph_run`).
4. Runner collects context and semantic memory.
5. Runner generates plan and operations using selected LLM provider.
6. Runner optionally applies edits (`edit-mode=apply`) with strict guards.
7. Runner runs gate checks (`lint`, `build`, `test`) depending on flags.
8. Runner computes memory snapshot and finalizes run.
9. Runner appends progress JSONL and updates feature backlog state.

Evidence:
- Script entry and argument defaults. (source: scripts/ralph_local_runner.mjs:39)
- Guard decision and effective edit mode. (source: scripts/ralph_local_runner.mjs:1040)
- Start run RPC call. (source: scripts/ralph_local_runner.mjs:1094)
- Plan and ops prompt pipeline. (source: scripts/ralph_local_runner.mjs:1351)
- Apply pipeline with line-bound find/replace constraints. (source: scripts/ralph_local_runner.mjs:1487)
- Gate execution. (source: scripts/ralph_local_runner.mjs:1576)
- Finish run RPC and health read. (source: scripts/ralph_local_runner.mjs:1707)
- Progress JSONL append. (source: scripts/ralph_local_runner.mjs:1813)

## 3. Command Surface

## 3.1 NPM Entry Points

- `ralph:local`: executes single local runner script.
- `ralph:loop`: executes Powershell loop wrapper.
- `ralph:memory:ingest`: chunks and upserts repository memory documents.
- `ralph:memory:query`: searches semantic memory for a query.

Evidence: package scripts. (source: package.json:18)

## 3.2 `ralph_local_runner` Argument Model

Default values from parser include:

- `mode=qa`
- `dryRun=true`
- `llmProvider=nvidia`
- `llmModel=moonshotai/kimi-k2.5`
- `scope=[csv,lookup]`
- `maxIterations=3`
- `timeoutMinutes=20`
- `editMode=propose`
- `editMaxFiles=2`
- `editAllowlist=[src/,index.html,docs/,public/]`
- `featureFile=docs/ralph/feature_backlog.json`
- `progressFile=docs/ralph/progress_log.jsonl`
- `semanticUseEmbeddings=true`
- `semanticEmbeddingProvider=nvidia`
- `semanticEmbeddingModel=nvidia/nv-embedqa-e5-v5`
- `applyRequireStableProposeRuns=5`
- `lockToNvidia=true`

Evidence: parser defaults. (source: scripts/ralph_local_runner.mjs:40)

## 3.3 Loop Supervisor

`ralph_loop.ps1` wraps repeated runner execution with:

- Duration and interval controls.
- Profile modes (`learn`, `propose`, `apply`).
- Failure stop threshold (`StopAfterConsecutiveFailures`).
- Summary aggregation per run in `scripts/_out/ralph_loop`.

Evidence:
- Loop parameters and profile mapping. (source: scripts/ralph_loop.ps1:1)
- Summary writing path and fields. (source: scripts/ralph_loop.ps1:157)

## 4. Safety and Guarding

## 4.1 Build Failure Signature Guard

Before executing apply mode, runner inspects recent failed progress rows and checks repeated build failure signatures. If repeated over threshold, edit mode is downgraded to `propose`.

Evidence:
- Signature extraction from build stderr. (source: scripts/ralph_local_runner.mjs:271)
- Guard evaluation. (source: scripts/ralph_local_runner.mjs:294)
- Downgrade decision. (source: scripts/ralph_local_runner.mjs:1053)

## 4.2 Apply Readiness Guard

Apply mode requires stable successful propose history (`applyRequireStableProposeRuns`, default 5). If threshold is not met, runner stays in `propose`.

Evidence:
- Apply readiness guard implementation. (source: scripts/ralph_local_runner.mjs:379)
- Effective edit mode override. (source: scripts/ralph_local_runner.mjs:1060)

## 4.3 Feature Loop Guard

Runner inspects repeated failures for the active feature and can rotate to another feature when repeated signature and changed-file signature loops are detected.

Evidence:
- Loop detection by feature id and signatures. (source: scripts/ralph_local_runner.mjs:411)
- Rotation logic and transition fields. (source: scripts/ralph_local_runner.mjs:1136)

## 4.4 Edit Application Constraints

Apply mode enforces strict constraints per operation:

- Path allowlist check.
- `find` minimum length.
- Single exact match required.
- Match must be line bounded.
- No-op replacements are rejected.

Evidence: guarded apply block. (source: scripts/ralph_local_runner.mjs:1490)

## 4.5 Branch Safety

Runner refuses `edit-mode=apply` on `main` and `master` unless non-main enforcement is explicitly disabled.

Evidence: branch guard. (source: scripts/ralph_local_runner.mjs:1074)

## 5. LLM and Embedding Providers

## 5.1 Provider Support

Runner supports chat providers:

- OpenAI via `/v1/responses`.
- Anthropic via `/v1/messages`.
- NVIDIA chat completions endpoint.

Evidence:
- OpenAI call implementation. (source: scripts/ralph_local_runner.mjs:887)
- Anthropic call implementation. (source: scripts/ralph_local_runner.mjs:914)
- NVIDIA call implementation. (source: scripts/ralph_local_runner.mjs:953)
- Dispatcher. (source: scripts/ralph_local_runner.mjs:986)

## 5.2 Semantic Embedding Support

Semantic memory query supports:

- `openai`
- `nvidia`
- `auto`
- `none`

Includes fallback to text-only retrieval when vector dimensional mismatch occurs.

Evidence:
- Provider resolution logic. (source: scripts/ralph_local_runner.mjs:793)
- Embedding call wrappers. (source: scripts/ralph_local_runner.mjs:723)
- Dimensional mismatch fallback. (source: scripts/ralph_local_runner.mjs:1277)

## 6. Operational Database Model

## 6.1 Tables

Operational tables:

- `public.ralph_runs`
- `public.ralph_actions`
- `public.ralph_eval_results`
- `public.ralph_incidents`

Key state semantics:

- Run status includes `running`, `completed`, `failed`, `cancelled`, `promotable`, `rolled_back`.
- Actions record phase/tool/target/latency/details.
- Eval rows record suite/metric/value/pass.
- Incidents track severity and resolution.

Evidence:
- Table DDL and status checks. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:3)

## 6.2 RLS and Policy Strategy

- RLS enabled on all operational tables.
- Authenticated `admin`/`editor` can read via policy.
- `service_role` has full policy access.

Evidence: policy declarations. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:76)

## 6.3 RPC Contract

Operational RPCs:

- `start_ralph_run`
- `finish_ralph_run`
- `record_ralph_action`
- `record_ralph_eval`
- `raise_ralph_incident`
- `resolve_ralph_incident`
- `get_ralph_health`

Evidence:
- Function declarations. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:204)
- Grants to authenticated and service_role. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:496)

## 7. Memory Model

## 7.1 Context Memory Tables

- `ralph_memory_snapshots`
- `ralph_memory_items`
- `ralph_memory_decisions`

Evidence: DDL. (source: supabase/migrations/20260218154000_ralph_memory_context.sql:7)

## 7.2 Semantic Document Table

`ralph_memory_documents` supports hybrid retrieval:

- `embedding vector(1536)` for vector similarity.
- generated `search_text` tsvector for text ranking.
- ivfflat index for vector search.
- GIN index for text search.

Evidence: DDL and indexes. (source: supabase/migrations/20260218182000_ralph_semantic_memory.sql:6)

## 7.3 Memory RPC Catalog

- `upsert_ralph_memory_item`
- `compute_ralph_memory_snapshot`
- `get_ralph_context_pack`
- `upsert_ralph_memory_document`
- `search_ralph_memory_documents`
- `get_ralph_semantic_context`

Evidence:
- Context migration RPCs. (source: supabase/migrations/20260218154000_ralph_memory_context.sql:172)
- Semantic migration RPCs. (source: supabase/migrations/20260218182000_ralph_semantic_memory.sql:86)

## 7.4 Context Pack Structure

`get_ralph_context_pack` returns:

- `health_24h` from `get_ralph_health`.
- `latest_snapshot` and `recent_snapshots`.
- top active/watch `memory_items`.
- open alerts from `system_alerts_current`.
- latest weekly reports.

Evidence: function body assembly. (source: supabase/migrations/20260218154000_ralph_memory_context.sql:424)

## 8. Semantic Memory Tooling

## 8.1 Ingest Script

`ralph_memory_ingest.mjs`:

- Walks configured directories.
- Filters by extension.
- Chunks file text with overlap.
- Optionally computes OpenAI embeddings.
- Upserts each chunk via `upsert_ralph_memory_document`.

Evidence:
- Defaults and include ext list. (source: scripts/ralph_memory_ingest.mjs:49)
- Embedding API call. (source: scripts/ralph_memory_ingest.mjs:128)
- RPC upsert call. (source: scripts/ralph_memory_ingest.mjs:208)

## 8.2 Query Script

`ralph_memory_query.mjs`:

- Accepts query text and scope.
- Optionally embeds query with OpenAI.
- Calls `search_ralph_memory_documents` RPC.

Evidence:
- Query args and validation. (source: scripts/ralph_memory_query.mjs:38)
- RPC search call. (source: scripts/ralph_memory_query.mjs:96)

## 9. Admin Center Integration

## 9.1 Route and UI Placement

There is no dedicated `/admin/ralph` route in route tree. Ralph is currently surfaced inside main admin overview page.

Evidence:
- Admin route tree does not include a separate Ralph route. (source: src/App.tsx:140)
- Ralph state hooks are part of `AdminOverview`. (source: src/pages/admin/AdminOverview.tsx:460)

## 9.2 Read Operations Used by UI

Admin page reads:

- `get_ralph_health` RPC.
- `ralph_runs` list.
- `ralph_actions` list.
- `ralph_eval_results` list.
- `ralph_incidents` list.
- snapshot/item/document/decision counts.

Evidence: fetch block. (source: src/pages/admin/AdminOverview.tsx:863)

## 10. Feature Backlog and Progress Artifacts

Runner expects backlog/progress artifacts:

- Feature backlog JSON at `docs/ralph/feature_backlog.json`.
- Progress JSONL at `docs/ralph/progress_log.jsonl`.

Feature lifecycle helpers implement:

- active feature selection by priority/failure count.
- mark pass, mark fail, block on repeated failure.
- progress update on successful non-terminal apply.

Evidence:
- File defaults. (source: scripts/ralph_local_runner.mjs:60)
- Feature helper functions. (source: scripts/ralph_local_runner.mjs:329)

Repository status note:

- `docs/ralph/` directory is not currently present in this tree.
- Behavior for missing feature file is coded and returns `feature_file_missing`.

Evidence:
- Missing-file path handling. (source: scripts/ralph_local_runner.mjs:344)

## 11. Environment Variables

## 11.1 Required for Runner and Memory

Common required variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Provider-dependent variables:

- `NVIDIA_API_KEY` for default lock-to-nvidia behavior.
- `OPENAI_API_KEY` for OpenAI embeddings and optional chat mode.
- `ANTHROPIC_API_KEY` when using anthropic provider.

Evidence:
- Mandatory env checks. (source: scripts/ralph_local_runner.mjs:180)
- Lock-to-nvidia hard requirement. (source: scripts/ralph_local_runner.mjs:1063)
- OpenAI env checks in memory scripts. (source: scripts/ralph_memory_ingest.mjs:129, scripts/ralph_memory_query.mjs:62)

## 11.2 Optional Provider Endpoint Overrides

Optional endpoint override envs supported:

- `OPENAI_EMBEDDINGS_URL`
- `NVIDIA_EMBEDDINGS_URL`
- `NVIDIA_EMBEDDING_INPUT_TYPE`
- `NVIDIA_CHAT_COMPLETIONS_URL`

Evidence: provider call wrappers. (source: scripts/ralph_local_runner.mjs:726)

## 12. Failure Modes and Recovery

## 12.1 Repeated Build Failures

Symptom:

- runs in apply mode are downgraded to propose.

Detection:

- `build_failure_guard_activated` incident.

Evidence:
- Incident raise call. (source: scripts/ralph_local_runner.mjs:1184)

Recovery:

1. Fix root build failure in referenced file/signature.
2. Run propose mode until stability threshold is reached.
3. Re-enable apply mode.

(source: scripts/ralph_local_runner.mjs:379)

## 12.2 No Changes Applied in Apply Mode

Symptom:

- run ends failed with `no_changes_applied` incident.

Evidence:
- no-change failure path. (source: scripts/ralph_local_runner.mjs:1678)

Recovery:

1. Inspect ops proposal file under run `patches/iter_*_ops.json`.
2. Verify `find` snippets are long, unique, and line bounded.
3. Re-run in propose mode and adjust constraints or candidate files.

(source: scripts/ralph_local_runner.mjs:1408)

## 12.3 Context Pack Unavailable

Symptom:

- runner logs warning action/eval for missing context pack.

Evidence:
- context error handling. (source: scripts/ralph_local_runner.mjs:1226)

Recovery:

1. Validate DB RPC `get_ralph_context_pack` availability.
2. Confirm service role permissions and migration state.

(source: supabase/migrations/20260218154000_ralph_memory_context.sql:424)

## 13. Security and Authorization Notes

- Core mutation RPCs are `SECURITY DEFINER`.
- RLS policies constrain authenticated read access to admin/editor.
- Service role is explicitly granted broad execution rights.

Evidence:
- Security definer declarations on operational and memory RPCs. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:215)
- Policy definitions for admin/editor read. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:87)

## 14. Discrepancies and Gaps

## 14.1 Frontend Route Gap

`Admin Center` does not expose a dedicated Ralph route despite comprehensive Ralph data available in `AdminOverview`.

Status: `DISCREPANCY` (visibility, not functionality).

Evidence:
- Route tree lacks `/admin/ralph`. (source: src/App.tsx:140)
- Ralph telemetry exists in overview page. (source: src/pages/admin/AdminOverview.tsx:863)

## 14.2 Feature Backlog Bootstrap

Backlog path defaults to `docs/ralph/feature_backlog.json`, but the directory/file is absent in this tree.

Status: runtime tolerant but operationally incomplete by default.

Evidence:
- Default feature path in args. (source: scripts/ralph_local_runner.mjs:60)
- Missing-file handling branch. (source: scripts/ralph_local_runner.mjs:344)

## 15. Documentation Confidence

- `x-doc-confidence: high` for DB schema, RPC signatures, and runner guard behavior.
- `x-doc-confidence: medium` for production deployment topology of Ralph executor host because runner is local-script based and host orchestration is not fully codified in infra manifests.

Evidence:
- Script-centric execution model. (source: scripts/ralph_loop.ps1:43)
