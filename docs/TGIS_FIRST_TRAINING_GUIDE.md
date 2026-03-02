# TGIS First Training Guide (fal Trainer v2)

This is the shortest safe path to train and publish cluster 01 with the new fal pipeline.

## 1) Prepare env
```bash
cd /workspace/epic-insight-engine
source /workspace/.venv_tgis/bin/activate
set -a; source ml/tgis/deploy/worker.env; set +a
python -m ml.tgis.train.preflight_check --config ml/tgis/configs/base.yaml
```

Required green checks:
1. DB connectivity
2. Supabase keys
3. `FAL_KEY` or `FAL_API_KEY`
4. `TGIS_WEBHOOK_URL` and `TGIS_WEBHOOK_SECRET`

## 2) Ensure dataset and references exist
```bash
python -m ml.tgis.pipelines.thumb_captioner --config ml/tgis/configs/base.yaml
python -m ml.tgis.pipelines.reference_sync --config ml/tgis/configs/base.yaml --top-n 3
python -m ml.tgis.pipelines.manifest_writer --config ml/tgis/configs/base.yaml
```

## 3) Queue training (cluster 01)
Use admin UI or API:
```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/tgis-admin-start-training" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"clusterId":1,"runMode":"manual","dryRun":false,"targetVersion":"v1.1.0","stepsOverride":2000,"learningRateOverride":0.0005}'
```

## 4) Submit queued run to fal
```bash
python -m ml.tgis.runtime.local_worker_supervisor --config ml/tgis/configs/base.yaml --max-training-runs 1 --poll-seconds 20
```

One-shot debug tick (optional):
```bash
python -m ml.tgis.runtime.process_training_queue --config ml/tgis/configs/base.yaml --max-runs 1
```

On Windows local dev, you can use helper scripts:
```bash
powershell -ExecutionPolicy Bypass -File ml/tgis/deploy/start_local_worker.ps1
powershell -ExecutionPolicy Bypass -File ml/tgis/deploy/ensure_local_worker.ps1
powershell -ExecutionPolicy Bypass -File ml/tgis/deploy/status_local_worker.ps1
powershell -ExecutionPolicy Bypass -File ml/tgis/deploy/stop_local_worker.ps1
```

Expected immediate state:
1. `status='running'`
2. `fal_request_id` filled
3. `dataset_zip_url` filled
4. `dataset_images_count` filled

## 5) Wait webhook completion
Check DB:
```bash
python - << 'PY'
import os, psycopg
conn = psycopg.connect(os.environ["SUPABASE_DB_URL"])
with conn, conn.cursor() as cur:
    cur.execute("""
      select id, cluster_id, status, fal_request_id, target_version, output_lora_url, error_text
      from public.tgis_training_runs
      where cluster_id = 1
      order by id desc
      limit 5
    """)
    for r in cur.fetchall():
      print(r)
PY
```

On success, webhook also upserts candidate:
```sql
select cluster_id, version, status, lora_fal_path
from public.tgis_model_versions
where cluster_id = 1
order by updated_at desc
limit 3;
```

## 6) Visual QA + manual promote
1. Generate samples from admin/front runtime.
2. If approved, promote candidate in `AdminTgisModels` or call `tgis-admin-promote-model`.

## 7) Validate production path
1. `tgis_cluster_registry` has active `lora_version` + `lora_fal_path`.
2. `tgis-generate` returns images at `1920x1080`.
3. `tgis_generation_log` entries are `success`.

## 8) Automatic reinforcement queue (nightly)
```bash
python -m ml.tgis.runtime.queue_score_reinforcement --config ml/tgis/configs/base.yaml
```

## 8) If trainer submit fails (payload limits)
Requeue with smaller cap:
```json
{
  "clusterId": 1,
  "stepsOverride": 2000,
  "learningRateOverride": 0.0005,
  "maxImagesOverride": 3000
}
```

The worker already has adaptive fallback (`all -> 4000 -> 3000 -> 2500`) for payload/timeout errors.
