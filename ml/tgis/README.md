# TGIS ML Workspace

Operational ML layer for TGIS (Thumbnail Generation Intelligence System).

## Scope
1. Curate thumbnail dataset from platform signals.
2. Run cloud visual clustering.
3. Generate training captions and manifests.
4. Train LoRA per cluster via `fal-ai/z-image-turbo-trainer-v2`.
5. Register model versions and apply quality gates.

## Current Training Baseline
1. Base model strategy: `Tongyi-MAI/Z-Image-Turbo`.
2. Trainer provider: `fal-ai/z-image-turbo-trainer-v2` (async + webhook).
3. Inference provider: `fal-ai/z-image/turbo/image-to-image/lora`.
4. Promotion policy: manual gate (`candidate -> active`).
5. Product output policy: `1920x1080`.

## Key Files
1. `ml/tgis/configs/base.yaml`
2. `ml/tgis/train/fal_trainer.py`
3. `ml/tgis/runtime/local_worker_supervisor.py`
4. `ml/tgis/pipelines/reference_sync.py`
5. `scripts/setup_tgis.sh`

## Minimal End-to-End Commands
```bash
# 1) Build visual pool and export cloud manifest
python -m ml.tgis.pipelines.build_visual_pool_ab --config ml/tgis/configs/base.yaml --min-unique-players 50 --window-days 14
python -m ml.tgis.pipelines.export_cloud_manifest --config ml/tgis/configs/base.yaml

# 2) Apply cloud clusters and prepare train datasets
python -m ml.tgis.pipelines.apply_visual_clusters --config ml/tgis/configs/base.yaml --input ml/tgis/artifacts/cloud/visual_clusters.csv
python -m ml.tgis.pipelines.thumb_downloader --config ml/tgis/configs/base.yaml --max-total 30000 --max-per-cluster 10000
python -m ml.tgis.pipelines.thumb_captioner --config ml/tgis/configs/base.yaml
python -m ml.tgis.pipelines.reference_sync --config ml/tgis/configs/base.yaml
python -m ml.tgis.pipelines.manifest_writer --config ml/tgis/configs/base.yaml

# 3) Queue training (edge) and run local worker supervisor
python -m ml.tgis.train.preflight_check --config ml/tgis/configs/base.yaml
python -m ml.tgis.runtime.local_worker_supervisor --config ml/tgis/configs/base.yaml --max-training-runs 1 --poll-seconds 20
```

## Deploy Notes
1. Use `ml/tgis/deploy/worker.env.example` as template.
2. Use Supabase pooler DB URL (`aws-...pooler.supabase.com:5432`) for IPv4 compatibility.
3. Required env for training queue: `TGIS_WEBHOOK_URL`, `TGIS_WEBHOOK_SECRET`, `FAL_KEY`/`FAL_API_KEY`.
4. Keep `runpod_train_cluster.py` only as legacy fallback during migration cycle.
