-- TGIS migration: fal trainer async pipeline + i2i reference support

-- 1) training run observability for fal async lifecycle
ALTER TABLE public.tgis_training_runs
  ADD COLUMN IF NOT EXISTS training_provider text NOT NULL DEFAULT 'fal',
  ADD COLUMN IF NOT EXISTS fal_request_id text NULL,
  ADD COLUMN IF NOT EXISTS dataset_zip_url text NULL,
  ADD COLUMN IF NOT EXISTS dataset_images_count int NULL,
  ADD COLUMN IF NOT EXISTS output_lora_url text NULL,
  ADD COLUMN IF NOT EXISTS webhook_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_tgis_training_runs_fal_request_id
  ON public.tgis_training_runs (fal_request_id);

CREATE INDEX IF NOT EXISTS idx_tgis_training_runs_status_provider
  ON public.tgis_training_runs (status, training_provider, created_at DESC);

-- 2) cluster default reference image for i2i
ALTER TABLE public.tgis_cluster_registry
  ADD COLUMN IF NOT EXISTS reference_image_url text NULL,
  ADD COLUMN IF NOT EXISTS reference_tag text NULL,
  ADD COLUMN IF NOT EXISTS reference_updated_at timestamptz NULL;

-- 3) top references per cluster/tag
CREATE TABLE IF NOT EXISTS public.tgis_reference_images (
  cluster_id int NOT NULL REFERENCES public.tgis_cluster_registry(cluster_id) ON DELETE CASCADE,
  tag_group text NOT NULL,
  rank int NOT NULL CHECK (rank >= 1 AND rank <= 20),
  link_code text NOT NULL,
  image_url text NOT NULL,
  quality_score numeric(12,6) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (cluster_id, tag_group, rank)
);

CREATE INDEX IF NOT EXISTS idx_tgis_reference_images_cluster_tag
  ON public.tgis_reference_images (cluster_id, tag_group, rank);

ALTER TABLE public.tgis_reference_images ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tgis_reference_images_service_all ON public.tgis_reference_images;
CREATE POLICY tgis_reference_images_service_all
  ON public.tgis_reference_images FOR ALL
  TO public
  USING ((auth.jwt() ->> 'role') = 'service_role')
  WITH CHECK ((auth.jwt() ->> 'role') = 'service_role');

DROP POLICY IF EXISTS tgis_reference_images_admin_select ON public.tgis_reference_images;
CREATE POLICY tgis_reference_images_admin_select
  ON public.tgis_reference_images FOR SELECT
  TO authenticated
  USING (public.is_admin_or_editor());

-- 4) runtime fields for trainer/generator defaults
ALTER TABLE public.tgis_runtime_config
  ADD COLUMN IF NOT EXISTS fal_trainer_model text NOT NULL DEFAULT 'fal-ai/z-image-turbo-trainer-v2',
  ADD COLUMN IF NOT EXISTS fal_generate_model text NOT NULL DEFAULT 'fal-ai/z-image/turbo/image-to-image/lora',
  ADD COLUMN IF NOT EXISTS i2i_strength_default numeric(4,3) NOT NULL DEFAULT 0.600,
  ADD COLUMN IF NOT EXISTS lora_scale_default numeric(4,3) NOT NULL DEFAULT 0.600;

UPDATE public.tgis_runtime_config
SET
  fal_trainer_model = COALESCE(NULLIF(fal_trainer_model, ''), 'fal-ai/z-image-turbo-trainer-v2'),
  fal_generate_model = COALESCE(NULLIF(fal_generate_model, ''), 'fal-ai/z-image/turbo/image-to-image/lora'),
  i2i_strength_default = COALESCE(i2i_strength_default, 0.600),
  lora_scale_default = COALESCE(lora_scale_default, 0.600),
  updated_at = now()
WHERE config_key = 'default';

-- 5) user-provided references (public bucket, user-scoped object paths)
INSERT INTO storage.buckets (id, name, public)
VALUES ('tgis-user-references', 'tgis-user-references', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can upload own tgis references'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Users can upload own tgis references"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'tgis-user-references'
        AND auth.uid()::text = (storage.foldername(name))[1]
      )
    $p$;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can read own tgis references'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Users can read own tgis references"
      ON storage.objects FOR SELECT
      USING (
        bucket_id = 'tgis-user-references'
        AND auth.uid()::text = (storage.foldername(name))[1]
      )
    $p$;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can delete own tgis references'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Users can delete own tgis references"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'tgis-user-references'
        AND auth.uid()::text = (storage.foldername(name))[1]
      )
    $p$;
  END IF;
END $$;

