# Backend A - Supabase Edge Functions Core Platform

Comprehensive code-backed documentation for the non-commerce edge backend surface.

This document covers Discover, DPPI (also called DDPI in internal naming), TGIS, and shared data API behavior.

## 1. Scope and System Boundary

Backend A in this repository is the set of Supabase Edge Functions registered in `supabase/config.toml` except `commerce`.

Evidence:
- Function registration list and `verify_jwt` flags. (source: supabase/config.toml:3)
- Function handlers under `supabase/functions/*/index.ts`. (source: supabase/functions/discover-data-api/index.ts:594)

## 2. Runtime Architecture

### 2.1 Edge Runtime Pattern

Each function is implemented as a Deno HTTP handler using `serve(...)` and returns JSON with CORS headers.

Evidence:
- Discover data API server entrypoint. (source: supabase/functions/discover-data-api/index.ts:594)
- Discover collector server entrypoint. (source: supabase/functions/discover-collector/index.ts:1242)
- TGIS generate server entrypoint. (source: supabase/functions/tgis-generate/index.ts:1961)

### 2.2 Data Split Bridge (App -> Data project)

Discover handlers can proxy execution to a separate data Supabase project when bridge env vars are present.

Key behaviors:
- Proxy enablement checks `DATA_SUPABASE_URL`, `DATA_SUPABASE_SERVICE_ROLE_KEY`, `INTERNAL_BRIDGE_SECRET`.
- Strict proxy mode fails closed when split intent is enabled and bridge is not usable.
- Internal bridge calls are marked with `x-internal-bridge-secret` and `x-bridge-hop`.

Evidence:
- Proxy decision logic. (source: supabase/functions/_shared/dataBridge.ts:37)
- Strict mode logic. (source: supabase/functions/_shared/dataBridge.ts:68)
- Bridge invocation headers. (source: supabase/functions/_shared/dataBridge.ts:116)

### 2.3 Access Strategy

Auth is layered:
- Edge gateway config (`verify_jwt`) in `supabase/config.toml`.
- In-function auth checks for role or bearer token in most sensitive handlers.

Evidence:
- Config-level JWT flags. (source: supabase/config.toml:3)
- Role gate in discover data API context builder. (source: supabase/functions/discover-data-api/index.ts:170)
- Role gate in TGIS admin handlers. (source: supabase/functions/tgis-admin-start-training/index.ts:79)

## 3. Function Inventory

The table below documents every Backend A function currently configured.

Legend:
- Auth column describes observed behavior from config + handler checks.
- `x-doc-status: incomplete` means request/response schema is dynamic or not fully typed in code.

| Function | Public Path | verify_jwt | Primary Auth Behavior | Handler | Notes |
|---|---|---|---|---|---|
| `ai-analyst` | `/functions/v1/ai-analyst` | `false` | Handler-specific auth, dynamic payload | `supabase/functions/ai-analyst/index.ts` | `x-doc-status: incomplete` |
| `discover-collector` | `/functions/v1/discover-collector` | `true` | service role or cron-safe mode path | `supabase/functions/discover-collector/index.ts:1242` | report orchestration modes |
| `discover-island-lookup` | `/functions/v1/discover-island-lookup` | `false` | public lookup flow with internal guards | `supabase/functions/discover-island-lookup/index.ts:454` | public feature endpoint |
| `discover-island-page` | `/functions/v1/discover-island-page` | `false` | public island page resolver | `supabase/functions/discover-island-page/index.ts:1170` | summary/full modes |
| `discover-report-ai` | `/functions/v1/discover-report-ai` | `true` | protected report AI generation | `supabase/functions/discover-report-ai/index.ts:66` | content generation stage |
| `discover-exposure-collector` | `/functions/v1/discover-exposure-collector` | `true` | service role + mode-specific auth | `supabase/functions/discover-exposure-collector/index.ts:635` | collector + maintenance |
| `discover-exposure-report` | `/functions/v1/discover-exposure-report` | `true` | protected report synthesis | `supabase/functions/discover-exposure-report/index.ts:163` | report section data |
| `discover-links-metadata-collector` | `/functions/v1/discover-links-metadata-collector` | `true` | protected metadata collector | `supabase/functions/discover-links-metadata-collector/index.ts:504` | metadata pipeline |
| `discover-report-rebuild` | `/functions/v1/discover-report-rebuild` | `true` | admin/editor role required | `supabase/functions/discover-report-rebuild/index.ts:664` | rebuild workflow |
| `discover-exposure-timeline` | `/functions/v1/discover-exposure-timeline` | `false` | public timeline read | `supabase/functions/discover-exposure-timeline/index.ts:63` | report visualization |
| `discover-enqueue-gap` | `/functions/v1/discover-enqueue-gap` | `true` | protected gap enqueue | `supabase/functions/discover-enqueue-gap/index.ts:44` | queue maintenance |
| `discover-cron-admin` | `/functions/v1/discover-cron-admin` | `false` | internal cron admin logic | `supabase/functions/discover-cron-admin/index.ts:79` | scheduler controls |
| `discover-data-api` | `/functions/v1/discover-data-api` | `false` | table/RPC ACL inside handler | `supabase/functions/discover-data-api/index.ts:594` | central data gateway |
| `discover-rails-resolver` | `/functions/v1/discover-rails-resolver` | `false` | public resolver behavior | `supabase/functions/discover-rails-resolver/index.ts:497` | live discover rails |
| `discover-island-lookup-ai` | `/functions/v1/discover-island-lookup-ai` | `false` | asynchronous AI lookup flow | `supabase/functions/discover-island-lookup-ai/index.ts:437` | lookup enrichment |
| `discover-panel-timeline` | `/functions/v1/discover-panel-timeline` | `false` | public panel timeline | `supabase/functions/discover-panel-timeline/index.ts:313` | public timeline |
| `discover-panel-intel-refresh` | `/functions/v1/discover-panel-intel-refresh` | `true` | protected refresh operation | `supabase/functions/discover-panel-intel-refresh/index.ts:60` | admin refresh |
| `discover-dppi-panel` | `/functions/v1/discover-dppi-panel` | `false` | public DPPI panel signal | `supabase/functions/discover-dppi-panel/index.ts:36` | DPPI public surface |
| `discover-dppi-island` | `/functions/v1/discover-dppi-island` | `false` | public DPPI island signal | `supabase/functions/discover-dppi-island/index.ts:38` | DPPI public surface |
| `dppi-refresh-batch` | `/functions/v1/dppi-refresh-batch` | `true` | admin/editor role checks in flow | `supabase/functions/dppi-refresh-batch/index.ts:93` | batch refresh |
| `dppi-train-dispatch` | `/functions/v1/dppi-train-dispatch` | `true` | admin/editor role checks in flow | `supabase/functions/dppi-train-dispatch/index.ts:68` | train dispatch |
| `dppi-health` | `/functions/v1/dppi-health` | `false` | handler performs role check for admin data | `supabase/functions/dppi-health/index.ts:82` | health + admin bundles |
| `dppi-release-set` | `/functions/v1/dppi-release-set` | `true` | admin/editor release controls | `supabase/functions/dppi-release-set/index.ts:141` | release channel updates |
| `dppi-worker-heartbeat` | `/functions/v1/dppi-worker-heartbeat` | `true` | worker authenticated heartbeat | `supabase/functions/dppi-worker-heartbeat/index.ts:54` | worker liveness |
| `tgis-generate` | `/functions/v1/tgis-generate` | `false` | bearer + commerce signature path checks | `supabase/functions/tgis-generate/index.ts:1961` | generation runtime |
| `tgis-health` | `/functions/v1/tgis-health` | `false` | admin/editor role gate for sensitive reads | `supabase/functions/tgis-health/index.ts:69` | training/model health |
| `tgis-skins-search` | `/functions/v1/tgis-skins-search` | `false` | public search endpoint | `supabase/functions/tgis-skins-search/index.ts:55` | skin library search |
| `tgis-skins-sync` | `/functions/v1/tgis-skins-sync` | `false` | sync secret or bearer auth | `supabase/functions/tgis-skins-sync/index.ts:99` | ingestion job |
| `tgis-admin-refresh-dataset` | `/functions/v1/tgis-admin-refresh-dataset` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-refresh-dataset/index.ts:79` | dataset refresh |
| `tgis-admin-start-training` | `/functions/v1/tgis-admin-start-training` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-start-training/index.ts:79` | enqueue training |
| `tgis-admin-training-run-action` | `/functions/v1/tgis-admin-training-run-action` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-training-run-action/index.ts:75` | cancel/delete run |
| `tgis-admin-promote-model` | `/functions/v1/tgis-admin-promote-model` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-promote-model/index.ts:113` | promote candidate |
| `tgis-admin-rollback-model` | `/functions/v1/tgis-admin-rollback-model` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-rollback-model/index.ts:75` | rollback active model |
| `tgis-admin-delete-model` | `/functions/v1/tgis-admin-delete-model` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-delete-model/index.ts:75` | delete non-active model |
| `tgis-admin-sync-manifest` | `/functions/v1/tgis-admin-sync-manifest` | `false` | explicit admin/editor guard | `supabase/functions/tgis-admin-sync-manifest/index.ts:75` | publish manifest |
| `tgis-training-webhook` | `/functions/v1/tgis-training-webhook` | `false` | `x-webhook-token` required | `supabase/functions/tgis-training-webhook/index.ts:72` | trainer callback |
| `tgis-edit-studio` | `/functions/v1/tgis-edit-studio` | `false` | bearer + ownership checks | `supabase/functions/tgis-edit-studio/index.ts:73` | edit transformations |
| `tgis-camera-control` | `/functions/v1/tgis-camera-control` | `false` | bearer + ownership checks | `supabase/functions/tgis-camera-control/index.ts:113` | framing transformations |
| `tgis-layer-decompose` | `/functions/v1/tgis-layer-decompose` | `false` | bearer + ownership checks | `supabase/functions/tgis-layer-decompose/index.ts:31` | layer extraction |
| `tgis-layer-download` | `/functions/v1/tgis-layer-download` | `false` | request validation + URL checks | `supabase/functions/tgis-layer-download/index.ts:29` | zip download assembly |
| `tgis-delete-asset` | `/functions/v1/tgis-delete-asset` | `false` | owner/admin check before delete | `supabase/functions/tgis-delete-asset/index.ts:4` | asset lifecycle cleanup |

Evidence for inventory derivation:
- Config list and verify flags. (source: supabase/config.toml:3)
- Serve entrypoints by function. (source: supabase/functions/discover-collector/index.ts:1242)

## 4. Core Data API (`discover-data-api`)

### 4.1 API Shape

Request shape sent by frontend:
- envelope `{ op, payload }`
- invoked through `supabase.functions.invoke("discover-data-api")`

Evidence:
- Frontend invocation contract. (source: src/lib/discoverDataApi.ts:60)
- Handler parses `op` and `payload`. (source: supabase/functions/discover-data-api/index.ts:624)

### 4.2 Supported Operations

The handler supports these operations:
- `select`
- `update`
- `delete`
- `upsert`
- `rpc`
- `public_report_bundle`
- `admin_overview_bundle`

Evidence:
- Switch statement with operation dispatch. (source: supabase/functions/discover-data-api/index.ts:658)

### 4.3 Access Control Matrix

Read/write access is table-scoped and enforced inside the handler.

Read buckets:
- public tables (`weekly_reports`, public discovery views)
- authenticated tables (`discover_reports`)
- admin tables (`discovery_exposure_targets`, `dppi_*`, etc.)

Write bucket:
- admin-only writes (`discover_reports`, `weekly_reports`, `discovery_panel_tiers`)

RPC bucket:
- allowlist only (`get_census_stats`, `admin_list_pipeline_crons`, etc.)

Evidence:
- Read/write table sets. (source: supabase/functions/discover-data-api/index.ts:28)
- RPC allowlist. (source: supabase/functions/discover-data-api/index.ts:62)
- Access enforcement. (source: supabase/functions/discover-data-api/index.ts:227)

### 4.4 Operation Contracts

#### `POST /functions/v1/discover-data-api` with `op=select`

- Auth: depends on selected table access level.
- Query params: none (all in JSON payload).
- Body schema (observed):
  - `table` (string, required)
  - `columns` (string, optional)
  - `filters` (array, optional)
  - `order` (array, optional)
  - `limit` (number, optional)
  - `single` (`single|maybeSingle`, optional)
- Response 200: `{ success: true, data, count? }`
- Error responses:
  - 400 unsupported op / invalid table or filter
  - 403 forbidden by ACL
- Side effects: none for select path.

Evidence:
- Select implementation and schema parsing. (source: supabase/functions/discover-data-api/index.ts:372)
- Error mapping. (source: supabase/functions/discover-data-api/index.ts:687)

#### `POST /functions/v1/discover-data-api` with `op=update|delete|upsert`

- Auth: admin table write ACL.
- Body schema: table + mutation-specific fields.
- Response 200: `{ success: true, data }`
- Error responses:
  - 400 invalid values/table/action
  - 403 forbidden by ACL
- Side effects: direct DB mutation in allowed tables.

Evidence:
- Update implementation. (source: supabase/functions/discover-data-api/index.ts:415)
- Delete implementation. (source: supabase/functions/discover-data-api/index.ts:438)
- Upsert implementation. (source: supabase/functions/discover-data-api/index.ts:458)

#### `POST /functions/v1/discover-data-api` with `op=rpc`

- Auth: allowlisted RPC + access level check.
- Body schema:
  - `fn` (string, required, allowlist)
  - `args` (object, optional)
- Response 200: `{ success: true, data }`
- Error responses:
  - 400 invalid/unsupported RPC
  - 403 access denied

Evidence:
- RPC validation and allowlist gate. (source: supabase/functions/discover-data-api/index.ts:484)

#### `POST /functions/v1/discover-data-api` with `op=public_report_bundle`

- Auth: none.
- Body schema:
  - `slug` (string, required)
- Response 200: merged report payload from `weekly_reports` and optional fallback from `discover_reports`.
- Error responses:
  - 400 missing slug
  - 400/500 report read failures
- Side effects: in-memory cache write.

Evidence:
- Public bundle logic. (source: supabase/functions/discover-data-api/index.ts:497)

#### `POST /functions/v1/discover-data-api` with `op=admin_overview_bundle`

- Auth: admin/service role.
- Body schema:
  - `forceRefresh` (boolean, optional)
- Response 200: admin overview payload + cache metadata.
- Side effects:
  - optional RPC refresh
  - in-memory cache update.

Evidence:
- Admin overview bundle and cache behavior. (source: supabase/functions/discover-data-api/index.ts:325)

### 4.5 `x-doc-status`

`discover-data-api` remains partially dynamic because payload schemas are runtime-validated, not typed via shared contract package.

- `x-doc-status: incomplete` for strict field-level response schemas.
- `x-doc-confidence: medium` for operation envelopes and ACL behavior.

Evidence:
- Dynamic payload access (`payload?.*`). (source: supabase/functions/discover-data-api/index.ts:625)

## 5. Discover Pipeline Endpoints

### 5.1 `discover-collector`

`discover-collector` implements a mode-based orchestration API:
- `start`
- `orchestrate`
- `catalog`
- `metrics`
- `finalize`

Auth behavior:
- allows service role
- allows cron-safe execution for safe modes

Evidence:
- Mode routing and cron-safe list. (source: supabase/functions/discover-collector/index.ts:1269)
- Phase dispatch from orchestrate mode. (source: supabase/functions/discover-collector/index.ts:1399)

Side effects:
- creates/updates reports
- claims and updates queue rows
- calls internal worker logic and downstream functions

Evidence:
- Queue claim RPC. (source: supabase/functions/discover-collector/index.ts:919)
- Queue status updates. (source: supabase/functions/discover-collector/index.ts:2045)

### 5.2 `discover-exposure-collector`

Mode-based endpoint with maintenance and diagnostics:
- `config_status`
- `set_paused`
- `bootstrap_device_auth`
- `maintenance`
- `intel_refresh`
- `diagnose_rating`
- `tick`
- `orchestrate`

Auth behavior:
- cron-safe for operational modes
- explicit admin/editor check for state-changing user modes

Evidence:
- Mode enum and dispatch. (source: supabase/functions/discover-exposure-collector/index.ts:27)
- Cron-safe and user-auth mode sets. (source: supabase/functions/discover-exposure-collector/index.ts:669)
- Role guard helper. (source: supabase/functions/discover-exposure-collector/index.ts:118)

### 5.3 Report Assembly Endpoints

- `discover-report-rebuild`: admin/editor rebuild workflow
- `discover-exposure-report`: exposure section generation
- `discover-report-ai`: narrative/AI stage

Evidence:
- Admin/editor guard in rebuild handler. (source: supabase/functions/discover-report-rebuild/index.ts:31)
- Report AI entrypoint. (source: supabase/functions/discover-report-ai/index.ts:66)

## 6. DPPI (DDPI) Backend Surface

DPPI endpoints in Backend A:
- `dppi-health`
- `dppi-refresh-batch`
- `dppi-train-dispatch`
- `dppi-release-set`
- `dppi-worker-heartbeat`
- public predictors: `discover-dppi-island`, `discover-dppi-panel`

Detailed model/training behavior is documented in `docs/DDPI_ML_SYSTEM.md`.

Evidence:
- DPPI function registrations. (source: supabase/config.toml:54)
- DPPI admin route usage in frontend. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)

## 7. TGIS Backend Surface

TGIS endpoints in Backend A include generation and admin model lifecycle:
- generation/edit endpoints (`tgis-generate`, `tgis-edit-studio`, `tgis-camera-control`, `tgis-layer-decompose`, `tgis-layer-download`, `tgis-delete-asset`)
- admin endpoints (`tgis-admin-*`)
- health/training callbacks (`tgis-health`, `tgis-training-webhook`)

Detailed runtime/training behavior is documented in `docs/TGIS_LLM_ML_SYSTEM.md`.

Evidence:
- TGIS registrations. (source: supabase/config.toml:75)
- Admin actions invoking TGIS endpoints. (source: src/pages/admin/tgis/AdminTgisModels.tsx:86)

## 8. Frontend -> Backend A Call Map

Direct frontend invocations include:
- Discover public APIs (`discover-rails-resolver`, `discover-island-page`, timelines)
- Discover admin APIs (`discover-collector`, `discover-report-*`, `discover-exposure-*`)
- DPPI admin APIs (`dppi-*`)
- TGIS APIs (`tgis-*`)

Evidence:
- Frontend invoke usage inventory. (source: src/hooks/queries/publicQueries.ts:63)
- Admin overview helper invoking protected functions. (source: src/pages/admin/AdminOverview.tsx:631)

## 9. Discrepancies and Contract Gaps

### 9.1 Frontend calls `tgis-rewrite-prompt` but function is not registered in `supabase/config.toml`

This is a deployment/config discrepancy:
- file exists: `supabase/functions/tgis-rewrite-prompt/index.ts`
- frontend calls it
- config currently omits `[functions.tgis-rewrite-prompt]`

Evidence:
- Frontend invocation. (source: src/pages/ThumbGenerator.tsx:361)
- Function file exists. (source: supabase/functions/tgis-rewrite-prompt/index.ts:63)
- Missing in config list. (source: supabase/config.toml:3)

`DISCREPANCY: frontend expects endpoint, deployment config may not expose it.`

### 9.2 Schema confidence gaps

Many edge functions have runtime-only validation and no shared typed request/response definitions.

- `x-doc-confidence: low` for strict body/response schema in mixed dynamic handlers.
- OpenAPI includes baseline method/path/errors, but full object fields can remain partial.

Evidence:
- Dynamic request bodies in handlers. (source: supabase/functions/discover-collector/index.ts:1269)

## 10. OpenAPI Coverage

Backend A OpenAPI file:
- `docs/openapi-backend-a.yaml`

Current status:
- broad endpoint path coverage present
- schema depth varies by function due dynamic handler contracts

Evidence:
- Spec file. (source: docs/openapi-backend-a.yaml:1)

## 11. API Documentation Compliance Summary

For Backend A functions, minimum fields are documented as follows:
- method/path: documented from route conventions and function names.
- auth: documented from `verify_jwt` + in-handler checks.
- response 200: documented as JSON success envelope where determinable.
- error responses: documented from explicit error branches in handlers.

Where field-level response schema is not explicit in code:
- `x-doc-status: incomplete`
- reason: runtime dynamic payloads and conditional branches.

Evidence:
- Central error return pattern in discover-data-api. (source: supabase/functions/discover-data-api/index.ts:686)
- Explicit branch errors in discover and tgis handlers. (source: supabase/functions/discover-exposure-collector/index.ts:693)
