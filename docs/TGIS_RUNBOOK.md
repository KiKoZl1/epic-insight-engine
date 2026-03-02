# TGIS Runbook (fal Trainer v2 + Z-Image-Turbo i2i)

## Goal
Run TGIS training and inference with:
1. Async training on `fal-ai/z-image-turbo-trainer-v2`
2. Manual model promotion (`candidate -> active`)
3. i2i inference on `fal-ai/z-image/turbo/image-to-image/lora`
4. Final output fixed at `1920x1080`

## Official Architecture
1. Admin queues training via `tgis-admin-start-training`
2. Worker consumes queue in `ml/tgis/runtime/process_training_queue.py`
3. Worker submits trainer job via `ml/tgis/train/fal_trainer.py`
4. fal calls `tgis-training-webhook` when job ends
5. Webhook updates `tgis_training_runs` and upserts `tgis_model_versions` as `candidate`
6. Admin promotes model manually via `tgis-admin-promote-model`
7. Runtime generation uses `tgis-generate` (i2i + LoRA + reference selection)

## Required Environment
Set in worker and edge env:
1. `SUPABASE_URL`
2. `SUPABASE_SERVICE_ROLE_KEY`
3. `SUPABASE_DB_URL` (worker only)
4. `FAL_KEY` (or `FAL_API_KEY`)
5. `TGIS_WEBHOOK_URL` (public URL for `tgis-training-webhook`)
6. `TGIS_WEBHOOK_SECRET`
7. `TGIS_FAL_TRAINER_MODEL` (optional override, default `fal-ai/z-image-turbo-trainer-v2`)

## First-Time Setup
1. Apply migrations:
```bash
supabase db push
```
2. Deploy functions:
```bash
supabase functions deploy tgis-admin-start-training
supabase functions deploy tgis-training-webhook
supabase functions deploy tgis-generate
```
3. Install/update worker deps:
```bash
pip install -r ml/tgis/requirements.txt
```
4. Validate worker preflight:
```bash
python -m ml.tgis.train.preflight_check --config ml/tgis/configs/base.yaml
```

## Dataset + Reference Sync
Run the data pipeline before training:
```bash
python -m ml.tgis.pipelines.thumb_pipeline --config ml/tgis/configs/base.yaml
python -m ml.tgis.pipelines.reference_sync --config ml/tgis/configs/base.yaml --top-n 3
python -m ml.tgis.pipelines.manifest_writer --config ml/tgis/configs/base.yaml
```

`reference_sync` populates:
1. `public.tgis_reference_images` (top images by cluster/tag)
2. `public.tgis_cluster_registry.reference_image_url` (cluster fallback)

## Queue and Process Training
1. Queue one cluster from admin or API (`tgis-admin-start-training`).
2. `clusterId` is mandatory. Bulk queue (`all clusters`) is intentionally disabled.
3. Run worker supervisor (recommended):
```bash
python -m ml.tgis.runtime.local_worker_supervisor --config ml/tgis/configs/base.yaml --max-training-runs 1 --poll-seconds 20
```
4. One-shot queue tick (fallback/debug only):
```bash
python -m ml.tgis.runtime.process_training_queue --config ml/tgis/configs/base.yaml --max-runs 1
```
5. Expect run transitions:
1. `queued`
2. `running` (with `fal_request_id`, `dataset_zip_url`, `dataset_images_count`)
3. `success` or `failed` after webhook callback

Local Windows auto-recovery:
```bash
powershell -ExecutionPolicy Bypass -File ml/tgis/deploy/ensure_local_worker.ps1
```
You can schedule this script every minute in Task Scheduler to keep worker always up.

## Manual Promotion
After visual QA:
1. Promote candidate version in admin page `AdminTgisModels`
2. Or call `tgis-admin-promote-model`
3. Confirm:
1. `tgis_model_versions.status='active'`
2. `tgis_cluster_registry.lora_version` and `lora_fal_path` updated
3. Manifest synced if requested

## Inference Behavior
`tgis-generate` uses i2i with this reference priority:
1. `referenceImageUrl` sent by user
2. `tgis_reference_images` top-3 by `cluster + tagHint`
3. `tgis_cluster_registry.reference_image_url`
4. Fail with `no_reference_image_available`

Output enforcement:
1. Function requests `1920x1080` from fal.
2. If provider returns other dimensions, function normalizes server-side via storage transform and returns `1920x1080`.

Security:
1. User references must come from `tgis-user-references` bucket
2. System fallback URLs allowed only for `cdn-*.qstv.on.epicgames.com`

## Operational Checks
1. Stuck `running` runs:
```sql
update public.tgis_training_runs
set status='failed', ended_at=now(), updated_at=now(), error_text='stale_running_cleanup'
where status='running' and ended_at is null and started_at < now() - interval '30 minutes';
```
2. Latest runs:
```sql
select id, cluster_id, status, fal_request_id, target_version, started_at, ended_at, error_text
from public.tgis_training_runs
order by id desc
limit 20;
```
3. Latest candidates:
```sql
select cluster_id, version, status, lora_fal_path, updated_at
from public.tgis_model_versions
order by updated_at desc
limit 20;
```

## Troubleshooting
1. `missing_tgis_webhook_url`: set `TGIS_WEBHOOK_URL` in worker env.
2. `forbidden` on webhook: `TGIS_WEBHOOK_SECRET` mismatch between worker and edge env.
3. `fal_train_submit_failed:*payload*`: rerun queue with smaller `maxImagesOverride`.
4. `cluster_model_missing` on generate: no active model promoted for that cluster.
5. `invalid_reference_image_url`: user reference URL not in whitelist.
6. 500 on `tgis-generate`: inspect `tgis_generation_log.error_text`.

## Reinforcement Loop
Nightly can auto-queue reinforcement retrains from new high-score rows in `training_metadata.csv`:
```bash
python -m ml.tgis.runtime.queue_score_reinforcement --config ml/tgis/configs/base.yaml
```

Config knobs (`base.yaml -> runtime`):
1. `reinforcement_min_new_rows`
2. `reinforcement_min_score`
3. `reinforcement_steps`
4. `reinforcement_learning_rate`
5. `reinforcement_max_images`

## Legacy Path
`ml/tgis/train/runpod_train_cluster.py` remains in repo as legacy fallback only.
