# DPPI ML System Documentation

End-to-end documentation for DPPI (Discover Placement Prediction Intelligence).

This document covers architecture, APIs, data model, training, inference, release control, worker runtime, and admin operations.

## 1. Scope and System Boundary

DPPI system includes:

- DPPI admin UI pages under `/admin/dppi/*`.
- DPPI edge functions (`dppi-health`, `dppi-refresh-batch`, `dppi-train-dispatch`, `dppi-release-set`, `dppi-worker-heartbeat`).
- Public DPPI signal endpoints (`discover-dppi-island`, `discover-dppi-panel`).
- DPPI database schema and RPCs.
- DPPI Python ML pipelines.

Evidence:
- Admin routes for DPPI. (source: src/App.tsx:147)
- Function registrations. (source: supabase/config.toml:60)
- DPPI ML package files. (source: ml/dppi/runtime.py:1)

## 2. High-Level Architecture

### 2.1 Runtime Layers

1. Data layer (Postgres tables and RPC functions).
2. Edge layer (admin and public HTTP handlers).
3. Worker layer (Python orchestrators and model pipelines).
4. UI layer (admin dashboards and controls).

Evidence:
- Data table family. (source: supabase/migrations/20260227113000_dppi_tables.sql:3)
- Edge health aggregator. (source: supabase/functions/dppi-health/index.ts:111)
- Worker orchestration tick. (source: ml/dppi/pipelines/worker_tick.py:25)
- Admin page function calls. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)

### 2.2 Core DPPI Tables

Core tables in authoritative schema migration:

- `dppi_training_dataset_meta`
- `dppi_feature_store_daily`
- `dppi_feature_store_hourly`
- `dppi_labels_entry`
- `dppi_labels_survival`
- `dppi_model_registry`
- `dppi_release_channels`
- `dppi_predictions`
- `dppi_survival_predictions`
- `dppi_opportunities`
- `dppi_training_log`
- `dppi_inference_log`
- `dppi_drift_metrics`
- `dppi_calibration_metrics`
- `dppi_feedback_events`
- `dppi_panel_families`

(source: supabase/migrations/20260227113000_dppi_tables.sql:3)

## 3. API Documentation

## 3.1 `dppi-health`

- Expected method from clients: `POST`.
- Handler file: `supabase/functions/dppi-health/index.ts`.
- Method enforcement: only `OPTIONS` is explicitly checked; other methods are accepted by code path.
- Auth strategy: service role shortcut OR authenticated admin/editor role.

Evidence:
- Handler and CORS preflight. (source: supabase/functions/dppi-health/index.ts:82)
- Role logic and `user_roles` lookup. (source: supabase/functions/dppi-health/index.ts:72)

### Request Body

Body may be empty object.

(source: src/pages/admin/dppi/AdminDppiOverview.tsx:28)

### Response 200 (shape)

Returns:

- `success`
- `overview`
- `training_readiness`
- `inference_recent`
- `training_recent`
- `release_channels`
- `cron_jobs`
- `worker_latest`
- `worker_recent`
- `as_of`

(source: supabase/functions/dppi-health/index.ts:132)

### Error Responses

- `403` forbidden when auth fails.
- `500` on internal errors.

(source: supabase/functions/dppi-health/index.ts:88)

### Side Effects

Read-only aggregation over RPC and table selects.

(source: supabase/functions/dppi-health/index.ts:111)

### Documentation Confidence

- `x-doc-confidence: high` for response fields and auth checks.
- `x-doc-confidence: medium` for strict method semantics (no hard method gate).

## 3.2 `dppi-refresh-batch`

- Expected method from clients/cron: `POST`.
- Handler file: `supabase/functions/dppi-refresh-batch/index.ts`.
- Auth strategy: service-role request required.

Evidence:
- Service-role request check. (source: supabase/functions/dppi-refresh-batch/index.ts:97)
- Handler entry. (source: supabase/functions/dppi-refresh-batch/index.ts:93)

### Body Controls

Important fields:

- `mode`: `refresh | feature_hourly | feature_daily | labels_daily | opportunities | cleanup`
- `region`
- `surfaceName`
- `batchTargets`
- `activeWithinHours`
- `keepDays` (cleanup)

Evidence:
- Mode parse and defaults. (source: supabase/functions/dppi-refresh-batch/index.ts:126)

### Side Effects by Mode

- `cleanup`: calls `dppi_cleanup_old_data`.
- feature modes: calls `compute_dppi_feature_store_hourly` and/or `compute_dppi_feature_store_daily`.
- label mode: calls `compute_dppi_labels_entry` and `compute_dppi_labels_survival`.
- opportunities mode: calls `seed_dppi_heuristic_predictions` and `materialize_dppi_opportunities`.

(source: supabase/functions/dppi-refresh-batch/index.ts:136)

### Error Responses

- `403` on missing service-role auth.
- `500` on RPC/processing failures.

(source: supabase/functions/dppi-refresh-batch/index.ts:99)

### Documentation Confidence

- `x-doc-confidence: high`.

## 3.3 `dppi-train-dispatch`

- Expected method from admin UI: `POST`.
- Handler file: `supabase/functions/dppi-train-dispatch/index.ts`.
- Auth strategy: service role OR admin/editor user role.

Evidence:
- Role resolution path. (source: supabase/functions/dppi-train-dispatch/index.ts:35)
- UI usage. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:83)

### Core Behavior

1. Resolve auth.
2. Validate readiness via `dppi_training_readiness` unless force mode service-role override.
3. Upsert model registry record.
4. Insert queued row into `dppi_training_log`.

Evidence:
- Readiness RPC call. (source: supabase/functions/dppi-train-dispatch/index.ts:118)
- Model registry upsert. (source: supabase/functions/dppi-train-dispatch/index.ts:149)
- Training log insert. (source: supabase/functions/dppi-train-dispatch/index.ts:163)

### Error Responses

- `403` forbidden or force mode restriction.
- `500` runtime errors.

(source: supabase/functions/dppi-train-dispatch/index.ts:115)

### Documentation Confidence

- `x-doc-confidence: high`.

## 3.4 `dppi-release-set`

- Expected method from admin UI: `POST`.
- Handler file: `supabase/functions/dppi-release-set/index.ts`.
- Auth strategy: admin/editor or service role.

Evidence:
- Role resolution and guard. (source: supabase/functions/dppi-release-set/index.ts:57)
- UI invocation. (source: src/pages/admin/dppi/AdminDppiReleases.tsx:53)

### Core Behavior

1. Load candidate model from `dppi_model_registry`.
2. Compare against current release channel model.
3. Enforce calibration and drift gates unless force mode with service role.
4. Update `dppi_release_channels`.
5. Update model status metadata.
6. Insert audit feedback event.

Evidence:
- Model registry read. (source: supabase/functions/dppi-release-set/index.ts:202)
- Release channel read/write. (source: supabase/functions/dppi-release-set/index.ts:223)
- Calibration metric read. (source: supabase/functions/dppi-release-set/index.ts:255)
- Drift metric read. (source: supabase/functions/dppi-release-set/index.ts:276)
- Feedback insert. (source: supabase/functions/dppi-release-set/index.ts:326)

### Error Responses

- `403` forbidden or force mode restrictions.
- `500` on validation or write failure.

(source: supabase/functions/dppi-release-set/index.ts:187)

### Documentation Confidence

- `x-doc-confidence: high`.

## 3.5 `dppi-worker-heartbeat`

- Expected method from workers: `POST`.
- Handler file: `supabase/functions/dppi-worker-heartbeat/index.ts`.
- Auth strategy: service-role required.

Evidence:
- Handler entry and service role check flow. (source: supabase/functions/dppi-worker-heartbeat/index.ts:54)

### Core Behavior

Calls RPC `dppi_report_worker_heartbeat` with host/resource metrics payload.

Evidence: RPC invocation payload. (source: supabase/functions/dppi-worker-heartbeat/index.ts:91)

### Error Responses

- `403` forbidden when auth check fails.
- `500` on RPC failure.

(source: supabase/functions/dppi-worker-heartbeat/index.ts:83)

### Documentation Confidence

- `x-doc-confidence: high`.

## 3.6 `discover-dppi-island` (Public DPPI API)

- Handler file: `supabase/functions/discover-dppi-island/index.ts`.
- Purpose: island-centric DPPI opportunity/survival output.

Core reads:

- `dppi_opportunities`
- `dppi_survival_predictions`
- presence segment/event tables for attempts/reentry context

Evidence:
- Opportunities query. (source: supabase/functions/discover-dppi-island/index.ts:84)
- Survival query. (source: supabase/functions/discover-dppi-island/index.ts:93)
- Presence history queries. (source: supabase/functions/discover-dppi-island/index.ts:105)

## 3.7 `discover-dppi-panel` (Public DPPI API)

- Handler file: `supabase/functions/discover-dppi-panel/index.ts`.
- Purpose: panel-centric opportunity and benchmark output.

Core reads:

- `dppi_opportunities` filtered by panel
- `dppi_get_panel_benchmark` RPC

Evidence:
- Opportunities query. (source: supabase/functions/discover-dppi-panel/index.ts:85)
- Benchmark RPC call. (source: supabase/functions/discover-dppi-panel/index.ts:94)

## 4. DB Schema and RPC Contracts

### 4.1 Service Role Guard

`_dppi_require_service_role` function is used by write-heavy RPCs.

(source: supabase/migrations/20260227150000_dppi_rpc_and_policies.sql:21)

### 4.2 Feature and Label RPCs

- `compute_dppi_feature_store_hourly`
- `compute_dppi_feature_store_daily`
- `compute_dppi_labels_entry`
- `compute_dppi_labels_survival`

(source: supabase/migrations/20260227150000_dppi_rpc_and_policies.sql:89)

### 4.3 Model and Opportunity RPCs

- `dppi_get_latest_model`
- `materialize_dppi_opportunities`
- `dppi_cleanup_old_data`
- `admin_dppi_overview`

(source: supabase/migrations/20260227150000_dppi_rpc_and_policies.sql:488)

### 4.4 Readiness and Benchmark RPCs

- `dppi_training_readiness`
- `dppi_get_panel_benchmark`
- `dppi_report_worker_heartbeat`

(source: supabase/migrations/20260227173000_dppi_readiness_benchmark_worker_and_materialize.sql:54)

### 4.5 Cron Setup

Granular cron migration includes DPPI weekly train jobs and supporting cadence jobs.

Evidence:
- Weekly entry/survival train cron entries in migration. (source: supabase/migrations/20260227174000_dppi_granular_crons.sql:69)

## 5. Admin UI to Backend Dependency Map

| Admin Page | Primary Calls | Key Tables/RPCs |
|---|---|---|
| `AdminDppiOverview` | `dppi-health`, `dppi-refresh-batch`, `dppi-train-dispatch` | overview/readiness/training/inference/release/heartbeat payload |
| `AdminDppiModels` | `dataSelect` | `dppi_model_registry` |
| `AdminDppiTraining` | `dppi-health`, `dppi-train-dispatch`, `dataSelect` | `dppi_training_log`, readiness |
| `AdminDppiInference` | `dppi-refresh-batch`, `dataSelect` | `dppi_inference_log`, `dppi_opportunities` |
| `AdminDppiReleases` | `dppi-release-set`, `dataSelect` | `dppi_release_channels`, `dppi_model_registry` |

Evidence:
- Overview calls. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)
- Models query. (source: src/pages/admin/dppi/AdminDppiModels.tsx:14)
- Training calls. (source: src/pages/admin/dppi/AdminDppiTraining.tsx:54)
- Inference refresh. (source: src/pages/admin/dppi/AdminDppiInference.tsx:44)
- Release call. (source: src/pages/admin/dppi/AdminDppiReleases.tsx:53)

## 6. ML Training and Inference Pipelines

## 6.1 Configuration

DPPI config sets:

- region/surface defaults
- split windows
- entry and survival horizons
- catboost params
- release gates (AUC/precision/brier/ece/psi)

(source: ml/dppi/configs/base.yaml:1)

## 6.2 Runtime Helpers

Runtime layer loads config, resolves DB DSN (`SUPABASE_DB_URL`), and can set `service_role` claim for DB operations.

Evidence:
- Config loader and runtime dataclass. (source: ml/dppi/runtime.py:62)
- DB env requirements. (source: ml/dppi/runtime.py:98)
- Service role claim set. (source: ml/dppi/runtime.py:107)

## 6.3 Entry Training

`train_entry_model.py` flow:

1. Check readiness.
2. Load entry dataset.
3. Train/evaluate model.
4. Persist model metrics and run status updates.

Evidence:
- Readiness call. (source: ml/dppi/train_entry_model.py:58)
- Dataset load. (source: ml/dppi/train_entry_model.py:65)
- Evaluation calls. (source: ml/dppi/train_entry_model.py:117)

## 6.4 Survival Training

`train_survival_model.py` mirrors entry flow for survival labels/horizons.

Evidence:
- Readiness call. (source: ml/dppi/train_survival_model.py:58)
- Survival dataset load. (source: ml/dppi/train_survival_model.py:65)

## 6.5 Calibration

`evaluate_and_calibrate.py`:

- checks readiness
- loads dataset by task
- fits calibration artifact
- writes calibration metrics

Evidence:
- Readiness check. (source: ml/dppi/evaluate_and_calibrate.py:71)
- Calibration metrics insert. (source: ml/dppi/evaluate_and_calibrate.py:123)

## 6.6 Batch Inference

`batch_inference.py`:

- loads features
- loads latest model/calibrators
- applies calibrators
- inserts prediction rows
- logs inference summary

Evidence:
- Calibrator loading/apply. (source: ml/dppi/batch_inference.py:88)
- Prediction inserts. (source: ml/dppi/batch_inference.py:152)
- Inference log write. (source: ml/dppi/batch_inference.py:157)

## 6.7 Worker Tick

`worker_tick.py` stage order:

- heartbeat
- queued train run execution
- inference
- drift

(source: ml/dppi/pipelines/worker_tick.py:34)

Queue executor selects oldest queued `dppi_training_log` row and dispatches to entry/survival train scripts.

(source: ml/dppi/pipelines/run_worker_once.py:22)

## 7. Worker Deployment

Systemd artifacts exist for periodic DPPI worker execution.

- service: `dppi-worker.service`
- timer: `dppi-worker.timer`
- installer script: `install_systemd.sh`

Evidence:
- install script writes systemd unit and timer. (source: ml/dppi/deploy/install_systemd.sh:26)
- service file executes worker tick. (source: ml/dppi/deploy/systemd/dppi-worker.service:12)
- timer schedule metadata in unit template. (source: ml/dppi/deploy/systemd/dppi-worker.timer:2)

## 8. Authentication and Authorization Summary

| Endpoint | Auth Model | Evidence |
|---|---|---|
| `dppi-health` | service role OR admin/editor | `isAdminOrService` logic |
| `dppi-refresh-batch` | service role only | service role request check |
| `dppi-train-dispatch` | service role OR admin/editor | `resolveAuth` logic |
| `dppi-release-set` | admin/editor or service role | role + force mode checks |
| `dppi-worker-heartbeat` | service role only | service auth check |

Evidence:
- `dppi-health`. (source: supabase/functions/dppi-health/index.ts:49)
- `dppi-refresh-batch`. (source: supabase/functions/dppi-refresh-batch/index.ts:97)
- `dppi-train-dispatch`. (source: supabase/functions/dppi-train-dispatch/index.ts:35)
- `dppi-release-set`. (source: supabase/functions/dppi-release-set/index.ts:57)
- `dppi-worker-heartbeat`. (source: supabase/functions/dppi-worker-heartbeat/index.ts:80)

## 9. Error and Recovery Patterns

Common failure classes:

- readiness blocks training
- feature/label data freshness insufficient
- release gate threshold failures
- worker heartbeat missing
- cleanup/job RPC failures

Evidence:
- readiness used before training queue insert. (source: supabase/functions/dppi-train-dispatch/index.ts:118)
- release gate checks use calibration/drift tables. (source: supabase/functions/dppi-release-set/index.ts:255)
- health endpoint surfaces worker heartbeat rows. (source: supabase/functions/dppi-health/index.ts:122)

## 10. Frontend/Backend Contract Notes

### 10.1 Method Confidence

Several handlers do not hard-enforce `POST`, but frontend calls use `supabase.functions.invoke`, which sends request bodies in POST-style usage.

- mark method confidence as medium where strict method gate is absent.

Evidence:
- CORS-only method guard in several handlers. (source: supabase/functions/dppi-health/index.ts:83)

### 10.2 DPPI Public APIs

Public panel/island DPPI handlers are enabled with `verify_jwt = false`.

Evidence: config toggles. (source: supabase/config.toml:54)

## 11. Discrepancy Check

No direct discrepancy found in this pass between DPPI admin frontend calls and registered DPPI function names.

Evidence:
- Frontend calls `dppi-health`, `dppi-refresh-batch`, `dppi-train-dispatch`, `dppi-release-set`. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)
- Functions are registered in config. (source: supabase/config.toml:60)

## 12. Not Determined From Code

The following are not explicitly represented in repository code:

- External SLA/SLO targets for DPPI response latency.
- Human release approval workflow outside force/role checks.

Both are marked unknown intentionally.

