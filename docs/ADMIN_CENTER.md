# Admin Center Technical Documentation

Comprehensive code-backed reference for the `/admin` surface.

## 1. Scope

The Admin Center is the operational control plane for:

- Discover operational metrics and moderation.
- DPPI prediction pipeline control.
- TGIS generation/training/model lifecycle.
- Commerce administration.
- Ralph runtime and memory observability.

Evidence:
- Admin route tree and page imports. (source: src/App.tsx:47)
- Admin nav items for these domains. (source: src/navigation/config.ts:140)

## 2. Access Control

Admin surface access is enforced by `AdminRoute`.

Rules:

1. Unauthenticated users are redirected to `/auth`.
2. Authenticated users without admin/editor role are redirected to `/app`.
3. Only `isAdmin || isEditor` can render admin pages.

Evidence:
- Guard logic implementation. (source: src/components/AdminRoute.tsx:15)

### 2.1 Role Source

Roles are loaded from `user_roles` in backend handlers for sensitive admin APIs.

Evidence:
- DPPI role checks. (source: supabase/functions/dppi-health/index.ts:72)
- TGIS admin role checks. (source: supabase/functions/tgis-admin-sync-manifest/index.ts:66)

## 3. Admin Route Map

All routes mounted under `/admin`:

| Route | Component | Domain | Notes |
|---|---|---|---|
| `/admin` | `AdminOverview` | cross-domain | Unified platform ops dashboard |
| `/admin/reports` | `AdminReportsList` | discover | Report management |
| `/admin/reports/:id/edit` | `AdminReportEditor` | discover | Report edit flow |
| `/admin/exposure` | `AdminExposureHealth` | discover | Exposure health |
| `/admin/intel` | `AdminIntel` | discover | Intel summaries |
| `/admin/panels` | `AdminPanelManager` | discover | Panel management |
| `/admin/dppi` | `AdminDppiOverview` | dppi | Pipeline summary and actions |
| `/admin/dppi/models` | `AdminDppiModels` | dppi | Model registry |
| `/admin/dppi/training` | `AdminDppiTraining` | dppi | Training queue/health |
| `/admin/dppi/inference` | `AdminDppiInference` | dppi | Inference logs and refresh |
| `/admin/dppi/drift` | `AdminDppiDrift` | dppi | Drift metrics |
| `/admin/dppi/calibration` | `AdminDppiCalibration` | dppi | Calibration metrics |
| `/admin/dppi/releases` | `AdminDppiReleases` | dppi | Channel release control |
| `/admin/dppi/feedback` | `AdminDppiFeedback` | dppi | Feedback/release events |
| `/admin/tgis` | `AdminTgisOverview` | tgis | Generation/training health |
| `/admin/tgis/clusters` | `AdminTgisClusters` | tgis | Cluster registry |
| `/admin/tgis/dataset` | `AdminTgisDataset` | tgis | Dataset runs |
| `/admin/tgis/training` | `AdminTgisTraining` | tgis | Training queue operations |
| `/admin/tgis/models` | `AdminTgisModels` | tgis | Model management |
| `/admin/tgis/inference` | `AdminTgisInference` | tgis | Generation logs |
| `/admin/tgis/thumb-tools` | `AdminTgisThumbTools` | tgis | Tool run telemetry |
| `/admin/tgis/costs` | `AdminTgisCosts` | tgis | Cost usage tables |
| `/admin/tgis/safety` | `AdminTgisSafety` | tgis | Blocklist and blocked outputs |
| `/admin/commerce` | `AdminCommerce` | commerce | Billing and credit admin |

Evidence: route declarations. (source: src/App.tsx:140)

## 4. Navigation Visibility Model

Admin nav section appears only for admin context and roles `editor`/`admin`.

Evidence:
- Admin section visibility flags. (source: src/navigation/config.ts:307)
- Admin item list includes DPPI/TGIS/Commerce. (source: src/navigation/config.ts:312)

## 5. Admin Overview (`/admin`)

`AdminOverview` is a cross-domain operational dashboard that aggregates metrics from multiple domains.

Notable Ralph telemetry loaded by this page:

- `get_ralph_health` RPC.
- `ralph_runs`, `ralph_actions`, `ralph_eval_results`, `ralph_incidents`.
- memory tables: `ralph_memory_snapshots`, `ralph_memory_items`, `ralph_memory_documents`, `ralph_memory_decisions`.

Evidence:
- Ralph state declarations. (source: src/pages/admin/AdminOverview.tsx:460)
- Ralph RPC call. (source: src/pages/admin/AdminOverview.tsx:878)
- Ralph table reads. (source: src/pages/admin/AdminOverview.tsx:880)

## 6. DPPI Admin Surface

## 6.1 Overview (`/admin/dppi`)

Main actions:

- Load health payload via `dppi-health`.
- Trigger refresh batch via `dppi-refresh-batch`.
- Queue training (`entry` and `survival`) via `dppi-train-dispatch`.

Evidence:
- Health call. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)
- Refresh action. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:66)
- Train dispatch action. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:83)

## 6.2 Models (`/admin/dppi/models`)

Reads `dppi_model_registry` with ordering by `updated_at`.

Evidence: data query. (source: src/pages/admin/dppi/AdminDppiModels.tsx:14)

## 6.3 Training (`/admin/dppi/training`)

Reads training log and readiness state and can queue training from page.

Evidence:
- Training log query path. (source: src/pages/admin/dppi/AdminDppiTraining.tsx:27)
- Health/readiness call through `dppi-health`. (source: src/pages/admin/dppi/AdminDppiTraining.tsx:33)
- Train dispatch call. (source: src/pages/admin/dppi/AdminDppiTraining.tsx:54)

## 6.4 Inference (`/admin/dppi/inference`)

Reads inference/opportunity views and can trigger refresh batch.

Evidence:
- Data selects. (source: src/pages/admin/dppi/AdminDppiInference.tsx:19)
- Refresh call. (source: src/pages/admin/dppi/AdminDppiInference.tsx:44)

## 6.5 Releases (`/admin/dppi/releases`)

Uses `dppi-release-set` for release channel assignment and gate-enforced promotion.

Evidence:
- Release function invocation. (source: src/pages/admin/dppi/AdminDppiReleases.tsx:53)
- Release handler table writes and checks. (source: supabase/functions/dppi-release-set/index.ts:202)

## 7. TGIS Admin Surface

## 7.1 Overview (`/admin/tgis`)

Main actions:

- Load aggregate health from `tgis-health`.
- Trigger dataset refresh via `tgis-admin-refresh-dataset`.

Evidence:
- Health call. (source: src/pages/admin/tgis/AdminTgisOverview.tsx:22)
- Refresh call. (source: src/pages/admin/tgis/AdminTgisOverview.tsx:42)

## 7.2 Clusters (`/admin/tgis/clusters`)

Reads `tgis_cluster_registry` and can trigger manifest sync.

Evidence:
- Cluster table read. (source: src/pages/admin/tgis/AdminTgisClusters.tsx:19)
- Manifest sync call. (source: src/pages/admin/tgis/AdminTgisClusters.tsx:33)

## 7.3 Dataset (`/admin/tgis/dataset`)

Reads `tgis_dataset_runs` and triggers refresh jobs.

Evidence:
- Dataset table read. (source: src/pages/admin/tgis/AdminTgisDataset.tsx:19)
- Refresh dataset function call. (source: src/pages/admin/tgis/AdminTgisDataset.tsx:36)

## 7.4 Training (`/admin/tgis/training`)

Reads queue and cluster metadata, triggers start/cancel/delete actions.

Evidence:
- `tgis_training_runs` read. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:30)
- Start function call. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)
- Run action calls. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:104)

## 7.5 Models (`/admin/tgis/models`)

Reads model/training/cluster tables and can promote, rollback, delete, and test generate.

Evidence:
- Model/training/cluster reads. (source: src/pages/admin/tgis/AdminTgisModels.tsx:33)
- Promote call. (source: src/pages/admin/tgis/AdminTgisModels.tsx:86)
- Rollback call. (source: src/pages/admin/tgis/AdminTgisModels.tsx:101)
- Delete call. (source: src/pages/admin/tgis/AdminTgisModels.tsx:113)
- Generate call. (source: src/pages/admin/tgis/AdminTgisModels.tsx:137)

## 7.6 Inference (`/admin/tgis/inference`)

Reads from `tgis_generation_log`.

Evidence: table query. (source: src/pages/admin/tgis/AdminTgisInference.tsx:21)

## 7.7 Safety (`/admin/tgis/safety`)

Reads and updates blocklist terms and inspects blocked generations.

Evidence:
- Blocklist reads. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:21)
- Blocklist upsert/update. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:45)

## 7.8 Thumb Tools (`/admin/tgis/thumb-tools`)

Reads `tgis_thumb_tool_runs` to display status, latency, cost, payloads.

Evidence: run table read. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)

## 8. Commerce Admin Surface

`/admin/commerce` exists in route tree and is role-gated by admin guard.

Evidence:
- Route mount in app tree. (source: src/App.tsx:164)

Detailed backend financial admin endpoints:

- `/functions/v1/commerce/admin/user-lookup`
- `/functions/v1/commerce/admin/user/{userId}`
- `/functions/v1/commerce/admin/credits/grant`
- `/functions/v1/commerce/admin/credits/debit`

Evidence: commerce route mapping. (source: supabase/functions/commerce/index.ts:1662)

## 9. Backend Dependencies of Admin Actions

### 9.1 DPPI Functions

- `dppi-health`
- `dppi-refresh-batch`
- `dppi-train-dispatch`
- `dppi-release-set`

Evidence: function registration and UI callsites. (source: supabase/config.toml:60, src/pages/admin/dppi/AdminDppiOverview.tsx:27)

### 9.2 TGIS Functions

- `tgis-health`
- `tgis-admin-refresh-dataset`
- `tgis-admin-start-training`
- `tgis-admin-training-run-action`
- `tgis-admin-promote-model`
- `tgis-admin-rollback-model`
- `tgis-admin-delete-model`
- `tgis-admin-sync-manifest`

Evidence: function registration and UI callsites. (source: supabase/config.toml:75, src/pages/admin/tgis/AdminTgisTraining.tsx:82)

## 10. Security Notes for Admin Center

### 10.1 Mixed Auth Enforcement

Some functions run with `verify_jwt = false` in config, but enforce role checks in code.

Evidence:
- `tgis-admin-*` verify_jwt disabled. (source: supabase/config.toml:87)
- Handler role checks using `user_roles`. (source: supabase/functions/tgis-admin-refresh-dataset/index.ts:69)

### 10.2 Service Role Paths

DPPI refresh and worker heartbeat support service-role auth shortcuts for automation.

Evidence:
- Service role request checks in refresh and heartbeat paths. (source: supabase/functions/dppi-refresh-batch/index.ts:36, supabase/functions/dppi-worker-heartbeat/index.ts:80)

## 11. Operational Risks and Monitoring Focus

### 11.1 DPPI Risk Signals

- Readiness blocked
- Training queue growth
- Inference failures
- Drift high counts

Evidence:
- Health payload includes readiness, training, inference, drift contexts. (source: supabase/functions/dppi-health/index.ts:111)

### 11.2 TGIS Risk Signals

- Generation error rate spikes
- Training stuck in queue/running
- Missing worker heartbeat
- Blocklist growth

Evidence:
- TGIS health computes 24h errors, latency, queue counts, and heartbeat. (source: supabase/functions/tgis-health/index.ts:80)
- Safety page reads blocked generations. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:25)

### 11.3 Ralph Risk Signals

- Open critical incidents
- run failure rates
- stale memory snapshots

Evidence:
- `get_ralph_health` provides incident and run aggregates. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:448)
- Admin overview computes and displays these signals. (source: src/pages/admin/AdminOverview.tsx:1382)

## 12. Discrepancy Reporting Policy

If frontend calls an endpoint that is not registered in `supabase/config.toml`, mark `DISCREPANCY`.

Current state observed in this pass:

- No direct discrepancy found for DPPI/TGIS admin callsites covered in this document.

Evidence:
- Callsites exist for listed functions. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)
- Functions exist in config. (source: supabase/config.toml:90)

## 13. Not Determined From Code

The following cannot be concluded from repository code:

- Human escalation policy for each admin incident type.
- On-call rotation ownership mapping.

Both are intentionally excluded as behavior assertions.

