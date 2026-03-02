# TGIS Migration Plan: RunPod -> fal Trainer v2

## Objective
Migrate TGIS training from RunPod/AI Toolkit to:
1. Trainer: `fal-ai/z-image-turbo-trainer-v2`
2. Runtime generation: `fal-ai/z-image/turbo/image-to-image/lora`
3. Model base strategy: `Tongyi-MAI/Z-Image-Turbo` + cluster LoRA

## Product Decisions
1. Async training with webhook callback.
2. Manual promotion only (`candidate -> active`).
3. Big-bang migration of generation path to i2i.
4. User reference image has priority.
5. Dynamic fallback references from cluster/tag top list.
6. Final output target is always `1920x1080`.

## Backend Components
1. `ml/tgis/train/fal_trainer.py`
   - Builds zipped image+caption dataset from `metadata.jsonl`
   - Deduplicates and ranks by quality
   - Uploads zip to fal
   - Submits async training with webhook
2. `ml/tgis/runtime/process_training_queue.py`
   - Consumes queued runs
   - Submits to fal trainer
   - Stores `fal_request_id`, `dataset_zip_url`, `dataset_images_count`
3. `supabase/functions/tgis-training-webhook`
   - Auth via `TGIS_WEBHOOK_SECRET`
   - Resolves run by `fal_request_id`
   - Marks run success/failure
   - Upserts `tgis_model_versions` as `candidate` on success
4. `supabase/functions/tgis-generate`
   - Uses i2i + LoRA
   - Selects reference by priority
   - Records runtime metadata and image dimensions

## Schema Additions
1. `tgis_training_runs`
   - `training_provider`
   - `fal_request_id`
   - `dataset_zip_url`
   - `dataset_images_count`
   - `output_lora_url`
   - `webhook_payload_json`
2. `tgis_cluster_registry`
   - `reference_image_url`
   - `reference_tag`
   - `reference_updated_at`
3. `tgis_reference_images`
   - Top-ranked references per cluster/tag
4. `tgis_runtime_config`
   - `fal_trainer_model`
   - `fal_generate_model`
   - `i2i_strength_default`
   - `lora_scale_default`

## Reference Pipeline
`ml/tgis/pipelines/reference_sync.py`:
1. Reads `training_metadata.csv`
2. Computes top-N by quality per `cluster_id + tag_group`
3. Upserts `tgis_reference_images`
4. Updates cluster default reference (`reference_image_url`)

## i2i Request Contract
Input accepted by `tgis-generate`:
1. `prompt`
2. `category`
3. `variants`
4. `tagHint` (optional)
5. `referenceImageUrl` (optional user override)

Reference priority:
1. User `referenceImageUrl` (whitelisted)
2. Top-3 from `tgis_reference_images` by cluster/tag
3. Cluster default reference from registry
4. Fail with `no_reference_image_available`

## Security
1. Webhook secret required (`TGIS_WEBHOOK_SECRET`)
2. User reference URL whitelist:
   - Supabase bucket `tgis-user-references`
   - Epic CDN fallback `cdn-*.qstv.on.epicgames.com`
3. Non-whitelisted reference URLs are rejected.

## Rollout Sequence
1. Apply DB migration.
2. Deploy `tgis-admin-start-training`, `tgis-training-webhook`, `tgis-generate`.
3. Run `reference_sync`.
4. Queue cluster 01 training.
5. Validate candidate output quality.
6. Promote manually.
7. Train remaining clusters.
8. Keep RunPod file as legacy fallback in cycle 1.
