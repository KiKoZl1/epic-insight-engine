# TGIS LLM and ML System Documentation

Comprehensive documentation for TGIS generation, prompt orchestration, training, model lifecycle, and admin operations.

## 1. Scope and Boundary

TGIS subsystem includes:

- User generation and editing tools (`tgis-generate`, `tgis-edit-studio`, `tgis-camera-control`, `tgis-layer-decompose`, `tgis-layer-download`, `tgis-delete-asset`, `tgis-rewrite-prompt`, `tgis-skins-search`, `tgis-skins-sync`).
- Admin operations (`tgis-health`, `tgis-admin-*`, `tgis-training-webhook`).
- Shared thumb tools runtime helper (`_shared/tgisThumbTools.ts`).
- TGIS database schema and migrations.
- TGIS Python runtime and training pipeline.

Evidence:
- Function registration in config. (source: supabase/config.toml:75)
- Shared helper module and tool handlers. (source: supabase/functions/_shared/tgisThumbTools.ts:1)
- TGIS runtime scripts under `ml/tgis`. (source: ml/tgis/runtime/worker_tick.py:1)

## 2. Architecture Overview

### 2.1 Layers

1. Frontend pages and admin pages.
2. Edge function API layer.
3. Shared helper layer for auth, storage, FAL calls, and run logging.
4. DB schema and RPC layer.
5. Python runtime for queue processing and trainer integration.

Evidence:
- Frontend admin routes for TGIS pages. (source: src/App.tsx:155)
- Shared helper capabilities. (source: supabase/functions/_shared/tgisThumbTools.ts:433)
- Queue processor and worker tick in Python runtime. (source: ml/tgis/runtime/process_training_queue.py:20)

### 2.2 Control Planes

TGIS has two control planes:

- Real-time generation/edit plane (user tool requests).
- Training/model plane (queued training and promotion workflows).

Evidence:
- Generation logs table usage in health/admin pages. (source: supabase/functions/tgis-health/index.ts:81)
- Training runs and model versions in admin pages. (source: src/pages/admin/tgis/AdminTgisModels.tsx:33)

## 3. Frontend Surface

### 3.1 User Tool Routes

Tool hub routes include:

- `/app/thumb-tools/generate`
- `/app/thumb-tools/edit-studio`
- `/app/thumb-tools/camera-control`
- `/app/thumb-tools/layer-decomposition`

Evidence: route map. (source: src/App.tsx:130)

### 3.2 Admin TGIS Routes

- `/admin/tgis`
- `/admin/tgis/clusters`
- `/admin/tgis/dataset`
- `/admin/tgis/training`
- `/admin/tgis/models`
- `/admin/tgis/inference`
- `/admin/tgis/thumb-tools`
- `/admin/tgis/costs`
- `/admin/tgis/safety`

Evidence: route map. (source: src/App.tsx:155)

## 4. Core API Catalog

## 4.1 `tgis-generate`

### Purpose

Primary generation endpoint for thumbnail output.

### Auth and Gate

- Resolves auth from bearer token.
- Enforces commerce gateway signature when enabled.

Evidence:
- Auth header extraction. (source: supabase/functions/tgis-generate/index.ts:195)
- Commerce gateway enforcement function and invocation. (source: supabase/functions/tgis-generate/index.ts:231, supabase/functions/tgis-generate/index.ts:1973)

### Runtime Config

Reads `tgis_runtime_config` with fields:

- `default_generation_cost_usd`
- `generate_provider`
- `nano_model`
- `openrouter_model`
- `context_boost_default`
- `max_skin_refs`
- `max_total_refs`

Evidence:
- Config select fields. (source: supabase/functions/tgis-generate/index.ts:755)
- Parsed defaults and clamps. (source: supabase/functions/tgis-generate/index.ts:764)

### Prompt and Intent Pipeline

- Reads cluster registry and taxonomy rules.
- Applies sanitization/policy checks and blocklist validation.
- Uses OpenRouter for intent/prompt assist where configured.

Evidence:
- Cluster registry query. (source: supabase/functions/tgis-generate/index.ts:774)
- Taxonomy rules query. (source: supabase/functions/tgis-generate/index.ts:798)
- OpenRouter key usage. (source: supabase/functions/tgis-generate/index.ts:1039)
- Blocklist terms query. (source: supabase/functions/tgis-generate/index.ts:1948)

### Side Effects

Writes and RPC side effects include:

- `tgis_generation_log` (queued/success/failure updates).
- `tgis_thumb_tool_runs` insertion/update.
- `tgis_thumb_assets` insertion.
- `tgis_record_generation_cost` RPC.
- `tgis_increment_skin_usage` RPC.

Evidence:
- Generation log writes. (source: supabase/functions/tgis-generate/index.ts:2107)
- Tool run writes. (source: supabase/functions/tgis-generate/index.ts:2230)
- Asset writes. (source: supabase/functions/tgis-generate/index.ts:2281)
- Cost RPC. (source: supabase/functions/tgis-generate/index.ts:2356)
- Skin usage RPC. (source: supabase/functions/tgis-generate/index.ts:2365)

### Response and Errors

- Returns structured success payload with generation identifiers and model metadata.
- Returns structured errors on auth, policy, provider, or storage failures.

Evidence:
- Handler error return pattern. (source: supabase/functions/tgis-generate/index.ts:2442)

### Method Confidence

`x-doc-confidence: medium` for strict method requirement because handler checks `OPTIONS` explicitly but does not enforce POST-only at top-level.

Evidence: CORS guard pattern. (source: supabase/functions/tgis-generate/index.ts:1961)

## 4.2 `tgis-edit-studio`

- Validates mode, asset ownership, and input assets.
- Calls provider through shared `callFalModel` helper.
- Updates tool run and generated asset record.

Evidence:
- Handler entry. (source: supabase/functions/tgis-edit-studio/index.ts:73)
- Ownership load. (source: supabase/functions/tgis-edit-studio/index.ts:102)
- FAL call. (source: supabase/functions/tgis-edit-studio/index.ts:186)
- Run updates. (source: supabase/functions/tgis-edit-studio/index.ts:224)

## 4.3 `tgis-camera-control`

- Applies camera angle normalization and provider schema adaptation.
- Calls FAL and persists output.

Evidence:
- Angle normalization helper usage. (source: supabase/functions/tgis-camera-control/index.ts:51)
- Provider call path. (source: supabase/functions/tgis-camera-control/index.ts:168)

## 4.4 `tgis-layer-decompose`

- Validates owned source asset.
- Calls provider for layer extraction.
- Persists tool run details and outputs.

Evidence:
- Handler entry. (source: supabase/functions/tgis-layer-decompose/index.ts:31)
- Ownership read. (source: supabase/functions/tgis-layer-decompose/index.ts:51)

## 4.5 `tgis-layer-download`

- Supports layer output download workflow.

Evidence: function is registered and deployed. (source: supabase/config.toml:120)

## 4.6 `tgis-delete-asset`

- Enforces ownership for non-admin users.
- Deletes records by `image_url` scope.

Evidence:
- Ownership guard branch. (source: supabase/functions/tgis-delete-asset/index.ts:24)
- Delete-by-image-url path. (source: supabase/functions/tgis-delete-asset/index.ts:35)

## 4.7 `tgis-rewrite-prompt`

- Rewrites user prompt via OpenRouter when key is available.
- Falls back to local rewrite strategy if provider call not available.
- Enforces per-hour rewrite rate limit behavior.

Evidence:
- OpenRouter call branch. (source: supabase/functions/tgis-rewrite-prompt/index.ts:157)
- Fallback branch. (source: supabase/functions/tgis-rewrite-prompt/index.ts:187)
- Rewrite log insert. (source: supabase/functions/tgis-rewrite-prompt/index.ts:200)

## 4.8 `tgis-skins-search`

- Reads query params/body and paginates results.
- Uses RPCs `tgis_get_top_skins` and `tgis_count_skins`.

Evidence:
- RPC usage. (source: supabase/functions/tgis-skins-search/index.ts:72)

## 4.9 `tgis-skins-sync`

- Pulls outfit catalog from external Fortnite API.
- Upserts into `tgis_skins_catalog`.
- Deactivates stale rows not in current sync batch.

Evidence:
- External fetch. (source: supabase/functions/tgis-skins-sync/index.ts:68)
- Upsert path. (source: supabase/functions/tgis-skins-sync/index.ts:90)
- Stale deactivate path. (source: supabase/functions/tgis-skins-sync/index.ts:170)

## 4.10 `tgis-health`

- Admin/editor/service scoped health summary endpoint.
- Aggregates generation, latency, cost, cluster, model, training, and heartbeat data.

Evidence:
- Auth role checks. (source: supabase/functions/tgis-health/index.ts:42)
- Aggregation queries in `Promise.all`. (source: supabase/functions/tgis-health/index.ts:80)

## 4.11 Admin Training/Model Endpoints

- `tgis-admin-start-training`
- `tgis-admin-training-run-action`
- `tgis-admin-promote-model`
- `tgis-admin-rollback-model`
- `tgis-admin-delete-model`
- `tgis-admin-refresh-dataset`
- `tgis-admin-sync-manifest`

All are role-gated by `user_roles` (`admin` or `editor`).

Evidence:
- Example role checks in handlers. (source: supabase/functions/tgis-admin-rollback-model/index.ts:66)
- Frontend call sites. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)

## 4.12 `tgis-training-webhook`

- Validates webhook token.
- Locates training run by `fal_request_id`.
- Updates training run success/failure.
- Upserts candidate model in `tgis_model_versions` on success.

Evidence:
- Webhook token check. (source: supabase/functions/tgis-training-webhook/index.ts:78)
- Run lookup. (source: supabase/functions/tgis-training-webhook/index.ts:89)
- Model upsert. (source: supabase/functions/tgis-training-webhook/index.ts:135)

## 5. Shared Runtime Helper (`_shared/tgisThumbTools.ts`)

## 5.1 Key Responsibilities

- auth/user resolution
- commerce gateway verification
- runtime config loader
- FAL invocation wrapper
- run and asset table helpers
- storage normalization helpers
- OpenRouter vision description fallback/cache

Evidence:
- Commerce gateway helper. (source: supabase/functions/_shared/tgisThumbTools.ts:93)
- Role resolution from `user_roles`. (source: supabase/functions/_shared/tgisThumbTools.ts:128)
- Runtime config loader. (source: supabase/functions/_shared/tgisThumbTools.ts:462)
- FAL call helper. (source: supabase/functions/_shared/tgisThumbTools.ts:433)
- Tool run insert/update helpers. (source: supabase/functions/_shared/tgisThumbTools.ts:503)
- Asset insert helper. (source: supabase/functions/_shared/tgisThumbTools.ts:568)
- Vision helper using OpenRouter. (source: supabase/functions/_shared/tgisThumbTools.ts:770)

## 5.2 Runtime Config Surface

Shared runtime config includes:

- generation defaults and model IDs
- camera model/steps
- layer model and count bounds

Evidence: config select columns. (source: supabase/functions/_shared/tgisThumbTools.ts:465)

## 6. Database Model

## 6.1 Foundation

TGIS schema foundation migration creates core data structures for:

- cluster registry
- dataset runs
- training runs
- model versions
- generation logs
- runtime config
- cost and usage tracking

Evidence: foundation migration entrypoint. (source: supabase/migrations/20260228103000_tgis_foundation.sql:3)

## 6.2 FAL Trainer Extension

Additional fields for FAL request status/progress are added in dedicated migration.

Evidence: FAL trainer migration file exists and extends trainer model path. (source: supabase/migrations/20260302083000_tgis_fal_trainer_i2i.sql:1)

## 6.3 Thumb Tools Extension

Thumb tool run and asset storage structures are added in thumb-tools foundation migration.

Evidence: thumb tools migration file. (source: supabase/migrations/20260304123000_tgis_thumb_tools_foundation.sql:1)

## 7. Admin UI Dependency Map

| Admin Page | Data Sources | Mutations |
|---|---|---|
| `AdminTgisOverview` | `tgis-health` | `tgis-admin-refresh-dataset` |
| `AdminTgisClusters` | `tgis_cluster_registry` | `tgis-admin-sync-manifest` |
| `AdminTgisDataset` | `tgis_dataset_runs` | `tgis-admin-refresh-dataset` |
| `AdminTgisTraining` | `tgis_training_runs`, `tgis_cluster_registry` | `tgis-admin-start-training`, `tgis-admin-training-run-action` |
| `AdminTgisModels` | `tgis_model_versions`, `tgis_training_runs`, `tgis_cluster_registry` | promote, rollback, delete, test generate |
| `AdminTgisInference` | `tgis_generation_log` | read-only |
| `AdminTgisSafety` | `tgis_blocklist_terms`, `tgis_generation_log` | upsert/update blocklist |
| `AdminTgisThumbTools` | `tgis_thumb_tool_runs` | read-only |

Evidence:
- Overview calls. (source: src/pages/admin/tgis/AdminTgisOverview.tsx:22)
- Training calls. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)
- Models calls. (source: src/pages/admin/tgis/AdminTgisModels.tsx:86)
- Safety writes. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:45)

## 8. Python ML and Runtime

## 8.1 Config Baseline

`ml/tgis/configs/base.yaml` defines:

- dataset and artifact paths
- scoring thresholds
- clustering mode
- caption provider/model
- trainer/provider models
- runtime reinforcement controls

Evidence:
- Caption provider and model. (source: ml/tgis/configs/base.yaml:35)
- Trainer models and defaults. (source: ml/tgis/configs/base.yaml:44)
- Runtime section. (source: ml/tgis/configs/base.yaml:79)

## 8.2 Worker Tick

`ml/tgis/runtime/worker_tick.py` executes:

1. heartbeat
2. training queue processing
3. cost sync

(source: ml/tgis/runtime/worker_tick.py:30)

## 8.3 Training Queue Processor

`ml/tgis/runtime/process_training_queue.py` controls:

- training enabled gate from `tgis_runtime_config`
- recluster quality gate
- queue claim transition to `running`
- submit to FAL trainer
- poll provider status and update progress
- success/failure terminal transitions
- candidate model upsert on completion

Evidence:
- training enabled lookup. (source: ml/tgis/runtime/process_training_queue.py:48)
- recluster gate check and failures. (source: ml/tgis/runtime/process_training_queue.py:63)
- queued->running claim. (source: ml/tgis/runtime/process_training_queue.py:470)
- submit call. (source: ml/tgis/runtime/process_training_queue.py:540)
- running poll path. (source: ml/tgis/runtime/process_training_queue.py:223)
- success transition and model upsert. (source: ml/tgis/runtime/process_training_queue.py:254)
- failed transitions. (source: ml/tgis/runtime/process_training_queue.py:300)

## 8.4 Preflight Checks

`ml/tgis/train/preflight_check.py` validates:

- env keys (`OPENROUTER_API_KEY`, `FAL_API_KEY`, `RUNPOD_API_KEY`)
- DB connection and cluster records
- runtime config `training_enabled`

Evidence:
- required env list. (source: ml/tgis/train/preflight_check.py:35)
- runtime training_enabled query. (source: ml/tgis/train/preflight_check.py:107)

## 8.5 FAL Trainer Integration

`ml/tgis/train/fal_trainer.py` supports:

- zip dataset creation
- upload via `fal_client`
- submit training request
- poll training status

Evidence:
- FAL key requirement. (source: ml/tgis/train/fal_trainer.py:25)
- submit call. (source: ml/tgis/train/fal_trainer.py:160)
- polling helper. (source: ml/tgis/train/fal_trainer.py:190)

## 8.6 RunPod Fallback Path

`ml/tgis/train/runpod_train_cluster.py` supports optional AI Toolkit execution path and writes training run status.

Evidence:
- AI toolkit runner and python path checks. (source: ml/tgis/train/runpod_train_cluster.py:60)
- training run insert/update logic. (source: ml/tgis/train/runpod_train_cluster.py:97)

## 9. LLM and Prompt System Details

### 9.1 OpenRouter Usage

OpenRouter is used in multiple parts:

- generation intent/prompt assistance
- skin vision context descriptions
- rewrite-prompt endpoint

Evidence:
- OpenRouter key usage in generate. (source: supabase/functions/tgis-generate/index.ts:1039)
- OpenRouter in shared vision helper. (source: supabase/functions/_shared/tgisThumbTools.ts:806)
- OpenRouter rewrite endpoint call. (source: supabase/functions/tgis-rewrite-prompt/index.ts:157)

### 9.2 Policy Constraints

Generate pipeline defines explicit policy constraints and text bans for overlays/UI and prohibited content.

Evidence: policy constants in generate function. (source: supabase/functions/tgis-generate/index.ts:161)

### 9.3 Blocklist Enforcement

Generate pipeline loads `tgis_blocklist_terms` to enforce blocked terms behavior.

Evidence: blocklist table access. (source: supabase/functions/tgis-generate/index.ts:1948)

## 10. Auth and Authorization Matrix

| Endpoint Class | Auth Model | Notes |
|---|---|---|
| user generation/edit tools | user token + ownership + optional commerce gateway | shared helper resolves user and ownership |
| admin tgis endpoints | admin/editor role check via `user_roles` | role enforced in code |
| training webhook | token-based webhook secret | does not rely on user session |
| skins-sync | secret or service/anon fallback policy | supports controlled automation |

Evidence:
- Role resolution helper. (source: supabase/functions/_shared/tgisThumbTools.ts:128)
- Admin role checks example. (source: supabase/functions/tgis-admin-refresh-dataset/index.ts:69)
- Webhook token enforcement. (source: supabase/functions/tgis-training-webhook/index.ts:78)
- Skins sync auth policy comments and logic. (source: supabase/functions/tgis-skins-sync/index.ts:114)

## 11. Observability and Cost Tracking

TGIS observability data sources include:

- `tgis_generation_log`
- `tgis_cost_usage_daily`
- `tgis_training_runs`
- `tgis_model_versions`
- `tgis_worker_heartbeat`
- `tgis_thumb_tool_runs`

Evidence:
- TGIS health aggregate query list. (source: supabase/functions/tgis-health/index.ts:80)
- Admin thumb tool run view. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)

## 12. Discrepancy Checks

### 12.1 Frontend Callers vs Registered Functions

No direct mismatch found for TGIS admin and core tool endpoints documented here.

Evidence:
- Frontend invokes registered functions such as `tgis-health`, `tgis-admin-start-training`, `tgis-admin-promote-model`. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)
- Functions are present in config. (source: supabase/config.toml:75)

### 12.2 Method Strictness

Some endpoints are operationally used as POST but do not explicitly reject non-POST methods except OPTIONS.

Mark method certainty medium where strict guard is absent.

Evidence: generate handler top-level method guard only handles OPTIONS. (source: supabase/functions/tgis-generate/index.ts:1961)

## 13. Not Determined From Code

The following are not fully derivable from repository code:

- External provider contractual quotas and pricing terms.
- Team operational ownership schedule for each TGIS incident class.

Both are intentionally excluded from definitive claims.

