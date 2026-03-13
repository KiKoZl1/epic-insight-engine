# Developer Guide

This guide describes how to safely change UEFN Toolkit using code-proven behavior.

## 1. Engineering Baseline

### 1.1 Application Stack

- Frontend: React + Vite + TypeScript. (source: package.json:69)
- Routing: React Router with explicit public, app, and admin trees. (source: src/App.tsx:100)
- Client data cache: TanStack React Query. (source: src/App.tsx:5)
- Backend API: Supabase Edge Functions by domain. (source: supabase/config.toml:3)
- Database: PostgreSQL migrations under `supabase/migrations`. (source: supabase/migrations/20260227113000_dppi_tables.sql:3)

### 1.2 Source of Truth Rule

Always treat these as authoritative, in order:

1. Migrations for schema and RPC contracts.
2. Edge function code for API behavior.
3. Frontend call sites for actual usage assumptions.
4. Docs only after code validation.

## 2. Route and Access Model

### 2.1 Public Surface

Public routes are mounted in app root and do not require auth.

Evidence: `/`, `/discover`, `/reports`, `/tools/*`. (source: src/App.tsx:103)

### 2.2 Authenticated App Surface

Workspace routes use `ProtectedRoute` and require valid session.

Evidence: `/app` route is wrapped by `ProtectedRoute`. (source: src/App.tsx:116)

### 2.3 Admin Surface

Admin routes use `AdminRoute` and require `admin` or `editor` role.

Evidence:
- Guard check in component. (source: src/components/AdminRoute.tsx:16)
- Admin route tree includes DPPI/TGIS/Commerce pages. (source: src/App.tsx:140)

## 3. Change Workflow

## 3.1 Before You Edit

1. Identify the domain impacted (`discover`, `dppi`, `tgis`, `ralph`, `commerce`, `frontend`).
2. Locate API boundary code first (`supabase/functions/*`).
3. Confirm schema dependencies (`supabase/migrations/*`).
4. Map UI call sites (`src/pages/**`, `src/lib/**`).
5. Define migration and backward compatibility strategy.

## 3.2 During Implementation

- Prefer additive migration strategy for production-safe rollouts.
- Keep edge handlers explicit on auth checks and error semantics.
- Preserve idempotency for credit-impacting endpoints.
- Update docs and OpenAPI specs after behavior changes.

Evidence:
- Frontend data helper dispatches structured ops to `discover-data-api`. (source: src/lib/discoverDataApi.ts:60)
- Tool execution paths use backend dispatch and credit operations in commerce backend. (source: supabase/functions/commerce/index.ts:717)

## 3.3 After Implementation

- Run lint/tests.
- Validate admin pages that consume changed tables/functions.
- Re-run any affected worker tick in dry/local mode if relevant.
- Update docs with source references.

## 4. Domain-Specific Development Notes

### 4.1 Discover Domain

- Core gateway from frontend to data operations is `discover-data-api` wrapper.
- If changing payload shape, update both wrapper and function contract.

Evidence: wrapper call shape `{ op, payload }`. (source: src/lib/discoverDataApi.ts:62)

### 4.2 DPPI Domain

- Training lifecycle uses queue table (`dppi_training_log`) and model registry.
- Admin UI expects health RPC payload plus recent logs.
- Release channel updates should enforce model/calibration/drift checks.

Evidence:
- DPPI training queue insertion in dispatch handler. (source: supabase/functions/dppi-train-dispatch/index.ts:163)
- DPPI health aggregates `admin_dppi_overview` and readiness RPC. (source: supabase/functions/dppi-health/index.ts:111)
- Release handler checks model registry/calibration/drift and writes feedback event. (source: supabase/functions/dppi-release-set/index.ts:202)

### 4.3 TGIS Domain

- Generation path performs auth resolution, commerce gate, intent/prompt pipeline, and logging.
- Admin training path manages queued/running/success/failed transitions in DB.
- Model promotion/rollback endpoints are role-gated.

Evidence:
- Commerce gateway enforcement in generate function. (source: supabase/functions/tgis-generate/index.ts:231)
- Runtime config read (`nano_model`, `openrouter_model`, ref limits). (source: supabase/functions/tgis-generate/index.ts:754)
- Training queue processor controls state transitions. (source: ml/tgis/runtime/process_training_queue.py:470)
- Admin promote/rollback handlers check `user_roles`. (source: supabase/functions/tgis-admin-promote-model/index.ts:66, supabase/functions/tgis-admin-rollback-model/index.ts:66)

### 4.4 Ralph Domain

- Ralph local runner is the orchestrator and writes run/action/eval/incident records via RPC.
- Memory subsystem uses snapshots + semantic documents.

Evidence:
- Runner calls `start_ralph_run`, `record_ralph_action`, `finish_ralph_run`. (source: scripts/ralph_local_runner.mjs:1094)
- Semantic search usage in runner. (source: scripts/ralph_local_runner.mjs:1268)
- Memory document upsert endpoint exists. (source: supabase/migrations/20260218182000_ralph_semantic_memory.sql:86)

### 4.5 Commerce Domain

- Commerce endpoint is a single edge function with internal routing.
- Tool execution includes debiting and optional reversal logic.

Evidence:
- Route handler block in commerce backend. (source: supabase/functions/commerce/index.ts:1563)
- Debit path in tool execute flow. (source: supabase/functions/commerce/index.ts:735)

## 5. Frontend Conventions

### 5.1 API Access Patterns

- Admin pages either call edge functions via `supabase.functions.invoke` or use data wrapper (`dataSelect`, `dataRpc`).

Evidence:
- DPPI overview invokes `dppi-health`. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)
- TGIS overview invokes `tgis-health`. (source: src/pages/admin/tgis/AdminTgisOverview.tsx:22)
- DPPI models page uses `dataSelect` on `dppi_model_registry`. (source: src/pages/admin/dppi/AdminDppiModels.tsx:14)

### 5.2 Navigation and Visibility

- Navigation items include role visibility constraints in central config.

Evidence: admin items visible to `editor` and `admin`. (source: src/navigation/config.ts:146)

## 6. Backend Conventions

### 6.1 Function Auth Pattern

Common edge function auth flow pattern:

1. Decode bearer/apikey and allow service-role short-circuit where applicable.
2. If not service-role, resolve user via Supabase auth.
3. Lookup role in `user_roles`.
4. Enforce domain role requirement (`admin/editor` for admin operations).

Evidence:
- DPPI health role check path. (source: supabase/functions/dppi-health/index.ts:49)
- TGIS admin role check path. (source: supabase/functions/tgis-admin-sync-manifest/index.ts:42)

### 6.2 Error Pattern

Most handlers return `{ success: false, error: <message> }` on failure.

Evidence:
- DPPI handlers return structured error payloads. (source: supabase/functions/dppi-health/index.ts:145)
- TGIS handlers return structured error payloads. (source: supabase/functions/tgis-training-webhook/index.ts:170)

## 7. Database and Migration Conventions

### 7.1 DPPI

- Tables prefixed `dppi_*`.
- RPCs enforce service role for write-heavy operations.
- Admin snapshot function `admin_dppi_overview` centralizes overview counters.

Evidence:
- DPPI table creation. (source: supabase/migrations/20260227113000_dppi_tables.sql:3)
- Service role guard function. (source: supabase/migrations/20260227150000_dppi_rpc_and_policies.sql:21)
- Overview function. (source: supabase/migrations/20260227150000_dppi_rpc_and_policies.sql:736)

### 7.2 TGIS

- Foundation migration defines core cluster/training/model/generation tables and RPCs.
- Follow-up migrations extend trainer integration and thumb tool storage.

Evidence:
- Foundation migration. (source: supabase/migrations/20260228103000_tgis_foundation.sql:3)
- FAL trainer fields migration. (source: supabase/migrations/20260302083000_tgis_fal_trainer_i2i.sql:1)
- Thumb tools foundation migration. (source: supabase/migrations/20260304123000_tgis_thumb_tools_foundation.sql:1)

### 7.3 Ralph

- Ops tables track runs, actions, evals, incidents.
- Memory context and semantic memory are separate migrations.

Evidence:
- Ops schema migration. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:3)
- Memory context schema migration. (source: supabase/migrations/20260218154000_ralph_memory_context.sql:7)
- Semantic memory migration. (source: supabase/migrations/20260218182000_ralph_semantic_memory.sql:6)

## 8. ML and Worker Development

### 8.1 DPPI Worker

Worker tick stages:

- heartbeat
- train queue execution
- inference
- drift

Evidence: stage list in orchestrator. (source: ml/dppi/pipelines/worker_tick.py:35)

### 8.2 TGIS Worker

Worker tick stages:

- heartbeat
- training queue process
- cost sync

Evidence: stage list in orchestrator. (source: ml/tgis/runtime/worker_tick.py:30)

### 8.3 Training Gates

TGIS queue processor can fail queued runs for:

- runtime training disabled
- recluster gate failure
- missing webhook URL
- submit failure

Evidence:
- `training_disabled_in_runtime_config`. (source: ml/tgis/runtime/process_training_queue.py:435)
- `recluster_gate_failed:*`. (source: ml/tgis/runtime/process_training_queue.py:459)
- `missing_tgis_webhook_url`. (source: ml/tgis/runtime/process_training_queue.py:529)
- `fal_train_submit_failed:*`. (source: ml/tgis/runtime/process_training_queue.py:603)

## 9. Documentation and API Update Rules

When changing behavior, update these artifacts in same branch:

- Relevant markdown docs under `docs/`.
- OpenAPI files (`openapi-backend-a.yaml` or `openapi-backend-b-commerce.yaml`) when request/response changes.
- Changelog entries for added/removed/breaking API behavior.
- `.doc-agent/state.json` snapshot for doc automation consistency.

## 10. Operational Safety Checklist

Before merge:

1. Confirm role and auth checks for any changed admin endpoint.
2. Confirm schema dependencies exist in migrations.
3. Confirm frontend call sites match request/response shape.
4. Confirm cost-impacting flows preserve idempotency and safe failure semantics.
5. Confirm worker paths log enough state for debugging.
6. Confirm docs reference updated file lines.

## 11. Links to Deep Domain Docs

- `ADMIN_CENTER.md`
- `DDPI_ML_SYSTEM.md`
- `TGIS_LLM_ML_SYSTEM.md`
- `RALPH_SYSTEM.md`
- `LLM_ML_RUNBOOK.md`
- `TOOLS_CATALOG.md`

## 12. Unknowns Policy

If you cannot prove a claim in code, mark it explicitly as `Not determined from code`.

Examples currently marked unknown:

- Complete external cloud deployment rollout contract.
- Out-of-repo incident policy documents.


