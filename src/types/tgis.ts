export type TgisImageVariant = {
  url: string;
  seed: number;
  width?: number;
  height?: number;
};

export type TgisGenerateRequest = {
  prompt: string;
  category: string;
  tagHint?: string;
  referenceImageUrl?: string;
  variants?: number;
  aspect_ratio?: "16:9";
};

export type TgisGenerateResponse = {
  success: boolean;
  generation_id?: string;
  cluster_id?: number;
  cluster_name?: string;
  model_version?: string | null;
  images?: TgisImageVariant[];
  cost_usd?: number;
  latency_ms?: number;
  rewritten_prompt?: string;
  reference_source?: string;
  reference_tag?: string | null;
  reference_url?: string;
  error?: string;
  reason?: string;
};

export type TgisClusterRegistryRow = {
  cluster_id: number;
  cluster_name: string;
  trigger_word: string;
  categories_json: string[];
  lora_version: string | null;
  lora_fal_path: string | null;
  reference_image_url?: string | null;
  reference_tag?: string | null;
  is_active: boolean;
  updated_at: string;
};

export type TgisModelVersion = {
  id: number;
  cluster_id: number;
  version: string;
  lora_fal_path: string;
  status: "draft" | "candidate" | "active" | "archived" | "failed";
  quality_gate_json: Record<string, unknown>;
  promoted_by: string | null;
  promoted_at: string | null;
  created_at: string;
  updated_at: string;
};

export type TgisTrainingRun = {
  id: number;
  cluster_id: number | null;
  status: "queued" | "running" | "success" | "failed" | "cancelled";
  run_mode: "manual" | "scheduled" | "dry_run";
  training_provider?: string;
  provider_status?: string | null;
  progress_pct?: number | null;
  eta_seconds?: number | null;
  elapsed_seconds?: number | null;
  estimated_cost_usd?: number | null;
  status_polled_at?: string | null;
  fal_request_id?: string | null;
  dataset_images_count?: number | null;
  output_lora_url?: string | null;
  target_version: string | null;
  error_text: string | null;
  created_at: string;
  started_at: string | null;
  ended_at: string | null;
};

export type TgisCostDaily = {
  day: string;
  provider: string;
  model_name: string;
  generations: number;
  images_generated: number;
  total_cost_usd: number;
  updated_at: string;
};
