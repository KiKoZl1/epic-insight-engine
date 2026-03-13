# LLM and ML Runbook

Operator runbook for ML and LLM subsystems: DPPI, TGIS, and Ralph.

This runbook is implementation-first and references only codified behavior.

## 1. Scope

Included systems:

- DPPI model lifecycle and worker orchestration.
- TGIS generation/training lifecycle and worker orchestration.
- Ralph autonomous run loop and semantic memory maintenance.

Evidence:
- DPPI runtime package and worker scripts. (source: ml/dppi/runtime.py:1)
- TGIS runtime package and training queue processor. (source: ml/tgis/runtime/process_training_queue.py:20)
- Ralph runner scripts and NPM entries. (source: package.json:18, scripts/ralph_local_runner.mjs:39)

## 2. System Map

## 2.1 Frontend Admin Control Plane

Admin routes driving ML/LLM operations:

- `/admin/dppi/*` for DPPI training, inference, releases.
- `/admin/tgis/*` for TGIS dataset, training, models, safety, costs.
- `/admin` includes Ralph telemetry widgets.

Evidence:
- Route declarations. (source: src/App.tsx:147)
- Ralph telemetry state in admin overview. (source: src/pages/admin/AdminOverview.tsx:460)

## 2.2 Edge Function API Plane

DPPI edge functions:

- `dppi-health`
- `dppi-refresh-batch`
- `dppi-train-dispatch`
- `dppi-release-set`
- `dppi-worker-heartbeat`

TGIS edge functions:

- user tools (`tgis-generate`, `tgis-edit-studio`, `tgis-camera-control`, `tgis-layer-*`, `tgis-rewrite-prompt`, `tgis-skins-*`)
- admin ops (`tgis-health`, `tgis-admin-*`, `tgis-training-webhook`)

Evidence: function registration. (source: supabase/config.toml:60)

## 2.3 Worker Plane

DPPI workers:

- `ml/dppi/pipelines/worker_tick.py` orchestrates heartbeat, training queue, inference, drift.
- `ml/dppi/pipelines/run_worker_once.py` consumes one queued training run.

TGIS workers:

- `ml/tgis/runtime/worker_tick.py` orchestrates heartbeat, training queue, cost sync.
- `ml/tgis/runtime/process_training_queue.py` claims queue rows, submits to FAL, polls status.

Ralph workers:

- local runner `scripts/ralph_local_runner.mjs`.
- loop supervisor `scripts/ralph_loop.ps1`.

Evidence:
- DPPI worker tick steps. (source: ml/dppi/pipelines/worker_tick.py:34)
- TGIS worker tick steps. (source: ml/tgis/runtime/worker_tick.py:30)
- Ralph loop wrapper. (source: scripts/ralph_loop.ps1:70)

## 3. Environment and Secrets

## 3.1 Core Project Variables

Minimum shared variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_DB_URL`

Evidence:
- `.env.example` baseline. (source: .env.example:5)
- DPPI runtime DSN requirements. (source: ml/dppi/runtime.py:98)
- TGIS runtime DSN requirements. (source: ml/tgis/runtime/__init__.py:75)

## 3.2 DPPI Worker Variables

Used by DPPI heartbeat and queue pipeline:

- `DPPI_WORKER_HOST`
- `DPPI_WORKER_SOURCE`
- `DPPI_QUEUE_DEPTH`
- `DPPI_TRAINING_RUNNING`
- `DPPI_INFERENCE_RUNNING`

Evidence: heartbeat payload construction. (source: ml/dppi/monitoring/worker_heartbeat.py:61)

## 3.3 TGIS Worker Variables

Critical TGIS vars:

- `TGIS_WEBHOOK_URL`
- `FAL_API_KEY` or `FAL_KEY`
- `OPENROUTER_API_KEY` for prompt/caption flows
- `TGIS_FAL_TRAINER_MODEL` optional override
- `TGIS_SKIP_RECLUSTER_GATE` optional bypass
- `TGIS_WORKER_HOST`
- `TGIS_WORKER_SOURCE`

Evidence:
- queue processor reads webhook and trainer env. (source: ml/tgis/runtime/process_training_queue.py:626)
- trainer key requirement path. (source: ml/tgis/train/fal_trainer.py:22)
- recluster gate skip env. (source: ml/tgis/runtime/process_training_queue.py:64)
- heartbeat worker env. (source: ml/tgis/runtime/heartbeat.py:16)

## 3.4 Ralph Variables

Critical Ralph vars:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `NVIDIA_API_KEY` (default locked mode)
- `OPENAI_API_KEY` for memory embeddings and optional LLM mode
- `ANTHROPIC_API_KEY` when using anthropic provider

Evidence:
- required env checks and lock-to-nvidia enforcement. (source: scripts/ralph_local_runner.mjs:1061)
- OpenAI usage in memory ingest/query scripts. (source: scripts/ralph_memory_ingest.mjs:129, scripts/ralph_memory_query.mjs:62)

## 4. Daily Startup Procedure

## 4.1 Validate Config and Secrets

1. Confirm `.env` (or environment manager) includes required variables.
2. Validate DB connectivity using worker runtime initialization.
3. Validate edge function deploy config includes required function registrations.

Evidence:
- runtime config loading behavior. (source: ml/dppi/runtime.py:63, ml/tgis/runtime/__init__.py:73)
- function registration map. (source: supabase/config.toml:3)

## 4.2 Quick Health Sweep

Run these checks:

1. Admin route access and role gate check (`/admin`).
2. DPPI health endpoint check (`dppi-health`).
3. TGIS health endpoint check (`tgis-health`).
4. Ralph health RPC check (`get_ralph_health`).

Evidence:
- admin role guard. (source: src/components/AdminRoute.tsx:15)
- DPPI and TGIS health handlers. (source: supabase/functions/dppi-health/index.ts:82, supabase/functions/tgis-health/index.ts:69)
- Ralph health RPC. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:448)

## 5. DPPI Operations

## 5.1 Queue Training from Admin

Admin UI queues training through `dppi-train-dispatch` with task type `entry` or `survival`.

Evidence:
- DPPI training page queue calls. (source: src/pages/admin/dppi/AdminDppiTraining.tsx:50)
- dispatch function behavior. (source: supabase/functions/dppi-train-dispatch/index.ts:101)

Expected dispatch outcomes:

- `queued=true` with run id when accepted.
- `409` blocked when readiness gate fails and `force=false`.

Evidence: readiness branch. (source: supabase/functions/dppi-train-dispatch/index.ts:129)

## 5.2 Training Worker Tick

`ml/dppi/pipelines/worker_tick.py` runs sequence:

1. heartbeat
2. train queue consumer
3. batch inference
4. drift job

Each step is optional via skip flags.

Evidence: step assembly. (source: ml/dppi/pipelines/worker_tick.py:34)

## 5.3 Queue Consumer

`run_worker_once.py`:

- selects oldest queued `dppi_training_log` row.
- picks entry vs survival training script by `task_type`.
- executes script with run id and model metadata.

Evidence: queue select and dispatch branch. (source: ml/dppi/pipelines/run_worker_once.py:21)

## 5.4 Model Training Scripts

Entry model:

- readiness check via `dppi_training_readiness`.
- temporal split.
- horizon training (`2h`, `5h`, `12h`).
- model registry upsert + training log finalize.

Evidence: entry script pipeline. (source: ml/dppi/train_entry_model.py:57)

Survival model:

- analogous flow with horizons `30m`, `60m`, `replace_lt_30m`.

Evidence: survival script pipeline. (source: ml/dppi/train_survival_model.py:57)

## 5.5 Calibration and Inference

Calibration command:

- `evaluate_and_calibrate.py` selects calibrator per horizon and writes calibration artifacts.

Evidence: calibrator selection and persistence. (source: ml/dppi/evaluate_and_calibrate.py:113)

Inference command:

- `batch_inference.py` loads channel release models, predicts, calibrates, writes prediction tables, and materializes opportunities.

Evidence:
- release lookup and prediction insert. (source: ml/dppi/batch_inference.py:77)
- opportunities materialization call. (source: ml/dppi/batch_inference.py:155)

## 5.6 DPPI Release Management

Release changes are made by `dppi-release-set`.

Core behavior:

- compare candidate and current release.
- evaluate calibration/drift gates.
- update `dppi_release_channels` and audit feedback.

Evidence: release set handler. (source: supabase/functions/dppi-release-set/index.ts:202)

## 6. TGIS Operations

## 6.1 Preflight Before Training

Run `ml/tgis/train/preflight_check.py` before starting training waves.

Checks include:

- required env keys.
- required artifacts and configs.
- DB active cluster and training_enabled checks.

Evidence: preflight checks list. (source: ml/tgis/train/preflight_check.py:30)

## 6.2 Queue Training from Admin

Admin UI uses `tgis-admin-start-training` with:

- `clusterId` required.
- optional `stepsOverride`, `learningRateOverride`, `maxImagesOverride`, `targetVersion`.
- `dryRun` mode support.

Evidence:
- frontend invoke payload. (source: src/pages/admin/tgis/AdminTgisTraining.tsx:82)
- backend validation and insert. (source: supabase/functions/tgis-admin-start-training/index.ts:95)

## 6.3 Training Queue Processor

`process_training_queue.py` behavior:

1. reads `training_enabled` from `tgis_runtime_config`.
2. claims queued row and marks `running`/`SUBMITTING`.
3. handles dry-run completion inline.
4. validates recluster gate when enabled.
5. submits FAL training request and stores request id.
6. polls running jobs and updates progress/provider status.
7. on completion, writes candidate model version row.

Evidence:
- training enabled read. (source: ml/tgis/runtime/process_training_queue.py:43)
- queue claim update. (source: ml/tgis/runtime/process_training_queue.py:465)
- submit call and DB update. (source: ml/tgis/runtime/process_training_queue.py:539)
- polling and completion update. (source: ml/tgis/runtime/process_training_queue.py:156)

## 6.4 Webhook Completion Path

`tgis-training-webhook`:

- verifies shared secret from query/header/bearer.
- resolves run by `fal_request_id`.
- marks run success/failed.
- upserts candidate row in `tgis_model_versions` on success.

Evidence:
- token check and request id extraction. (source: supabase/functions/tgis-training-webhook/index.ts:72)
- success update and model upsert. (source: supabase/functions/tgis-training-webhook/index.ts:106)

## 6.5 Model Promotion and Rollback

Promotion endpoint:

- `tgis-admin-promote-model` calls `tgis_set_active_model` and optionally syncs manifest.

Rollback endpoint:

- `tgis-admin-rollback-model` calls `tgis_rollback_model`.

Evidence:
- promote RPC call. (source: supabase/functions/tgis-admin-promote-model/index.ts:127)
- rollback RPC call. (source: supabase/functions/tgis-admin-rollback-model/index.ts:88)
- foundational RPC definitions. (source: supabase/migrations/20260228103000_tgis_foundation.sql:519)

## 6.6 Nightly and Scheduled Pipelines

Nightly orchestrator runs:

- heartbeat
- visual pool build
- thumb pipeline
- cloud manifest export
- cost sync
- reference sync
- optional reinforcement queue

Evidence: nightly script sequence. (source: ml/tgis/runtime/nightly_pipeline.py:23)

Quarterly retrain script queues scheduled or dry-run training rows for all active clusters.

Evidence: quarterly queue script. (source: ml/tgis/runtime/quarterly_retrain.py:22)

Score reinforcement script queues retrain when new high-score rows exceed thresholds.

Evidence: reinforcement queue logic. (source: ml/tgis/runtime/queue_score_reinforcement.py:170)

## 7. Ralph Operations

## 7.1 Single Run

Run once:

```bash
npm run ralph:local -- --mode=qa --dry-run=false --edit-mode=propose
```

Runner behavior includes:

- context + semantic memory enrichment.
- iterative plan and optional ops proposal/apply.
- gate execution and run finalization.

Evidence: main orchestration loop. (source: scripts/ralph_local_runner.mjs:1345)

## 7.2 Continuous Loop

Run loop:

```bash
npm run ralph:loop -- -DurationMinutes 60 -IntervalSeconds 300 -Profile propose
```

Loop writes run summary JSON under `scripts/_out/ralph_loop/run_<timestamp>/`.

Evidence: loop output path and summary write. (source: scripts/ralph_loop.ps1:44)

## 7.3 Semantic Memory Maintenance

Ingest repository knowledge:

```bash
npm run ralph:memory:ingest -- --paths=docs,src,supabase/migrations --max-files=400
```

Query semantic memory:

```bash
npm run ralph:memory:query -- --query="what failed in last runs" --scope=project,ralph
```

Evidence:
- ingest defaults and upsert call. (source: scripts/ralph_memory_ingest.mjs:49)
- query RPC call. (source: scripts/ralph_memory_query.mjs:96)

## 8. Incident Playbooks

## 8.1 DPPI Training Blocked

Signal:

- `dppi-train-dispatch` returns blocked/readiness payload.

Immediate checks:

1. run `dppi-health` and inspect `training_readiness`.
2. verify feature and label pipelines are producing fresh rows.
3. validate `minDays` input for dispatch.

Evidence:
- readiness RPC in dispatch handler. (source: supabase/functions/dppi-train-dispatch/index.ts:118)
- readiness table function declaration. (source: supabase/migrations/20260227173000_dppi_readiness_benchmark_worker_and_materialize.sql:187)

## 8.2 TGIS Queue Stuck in Running

Signal:

- many `running` rows with stale `status_polled_at`.

Immediate checks:

1. verify `process_training_queue.py` is running.
2. verify FAL credentials.
3. verify webhook URL and secret.
4. manually poll provider status through process script execution.

Evidence:
- polling updates `status_polled_at`. (source: ml/tgis/runtime/process_training_queue.py:338)
- webhook secret enforcement. (source: supabase/functions/tgis-training-webhook/index.ts:76)

## 8.3 Ralph Apply Downgraded Repeatedly

Signal:

- runner summary reports guard activated and effective mode `propose`.

Immediate checks:

1. inspect `build_failure_signature` in progress JSONL.
2. fix repeating build failure before re-enabling apply.
3. confirm stable propose streak reaches threshold.

Evidence:
- guard summary output. (source: scripts/ralph_local_runner.mjs:1853)
- progress fields include build failure signature. (source: scripts/ralph_local_runner.mjs:1836)

## 9. Operational Checklists

## 9.1 Start-of-Day Checklist

1. Verify admin access and role hydration.
2. Verify DPPI and TGIS health endpoints.
3. Verify latest worker heartbeat rows.
4. Verify no critical open Ralph incidents.

Evidence:
- admin role guard. (source: src/components/AdminRoute.tsx:15)
- worker heartbeat tables in health views. (source: supabase/functions/dppi-health/index.ts:125, supabase/functions/tgis-health/index.ts:92)
- Ralph incidents in health RPC. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:484)

## 9.2 Before Release Promotion

DPPI:

1. confirm candidate model in registry.
2. confirm calibration and drift metrics are within gate limits.
3. run release-set call and inspect response.

Evidence: release-set gate reads. (source: supabase/functions/dppi-release-set/index.ts:255)

TGIS:

1. confirm training run success and output LoRA URL.
2. confirm model version row exists as candidate.
3. promote with sync-manifest enabled.

Evidence:
- successful webhook requires LoRA URL. (source: supabase/functions/tgis-training-webhook/index.ts:106)
- promote path syncs manifest by default. (source: supabase/functions/tgis-admin-promote-model/index.ts:124)

## 9.3 End-of-Day Checklist

1. DPPI inference log inserted for latest bucket.
2. TGIS queue has no unbounded stuck rows.
3. Ralph run health is stable in last 24h.

Evidence:
- DPPI inference logging function. (source: ml/dppi/mlops.py:628)
- TGIS running queue monitoring in health endpoint. (source: supabase/functions/tgis-health/index.ts:89)
- Ralph health window in RPC. (source: supabase/migrations/20260216123000_ralph_ops_foundation.sql:448)

## 10. Cross-System Discrepancies

## 10.1 Admin Route Coverage

There is no dedicated route `/admin/ralph`; Ralph is embedded in main overview only.

Status: `DISCREPANCY` (UX/visibility).

Evidence:
- admin routes list. (source: src/App.tsx:140)
- Ralph fetch block in overview component. (source: src/pages/admin/AdminOverview.tsx:863)

## 10.2 TGIS Auth Config vs Handler Auth

Multiple TGIS admin functions are configured with `verify_jwt=false` but still enforce role checks inside handler logic.

Status: documented implementation behavior.

Evidence:
- config disables verify_jwt. (source: supabase/config.toml:87)
- handlers run explicit auth resolution. (source: supabase/functions/tgis-admin-start-training/index.ts:45)

## 11. Not Determined from Code

The following are not fully determined from repository code alone:

- external scheduler definition for production cron cadence outside script invocations.
- external alert routing integrations (Slack/PagerDuty/Datadog) wiring.
- multi-host worker leader-election strategy.

Marking policy: `Not determined from code`.

## 12. Documentation Confidence

- `x-doc-confidence: high` for command surfaces, DB/RPC contracts, and handler logic.
- `x-doc-confidence: medium` for production runtime topology details not fully represented in IaC manifests.
