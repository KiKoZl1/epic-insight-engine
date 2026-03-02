import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-token",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function mustEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

function extractBearer(req: Request): string {
  const authHeader = (req.headers.get("Authorization") || req.headers.get("authorization") || "").trim();
  return authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
}

function getWebhookToken(req: Request): string {
  const url = new URL(req.url);
  return (
    url.searchParams.get("token")?.trim() ||
    req.headers.get("x-webhook-token")?.trim() ||
    extractBearer(req) ||
    ""
  );
}

function normalizeStatus(input: unknown): "success" | "failed" {
  const s = String(input || "").toUpperCase().trim();
  if (["OK", "COMPLETED", "SUCCESS", "DONE"].includes(s)) return "success";
  return "failed";
}

function extractRequestId(payload: any): string {
  return String(
    payload?.request_id ||
      payload?.requestId ||
      payload?.data?.request_id ||
      payload?.payload?.request_id ||
      payload?.result?.request_id ||
      "",
  ).trim();
}

function extractLoraUrl(payload: any): string | null {
  const candidates = [
    payload?.diffusers_lora_file?.url,
    payload?.payload?.diffusers_lora_file?.url,
    payload?.data?.diffusers_lora_file?.url,
    payload?.result?.diffusers_lora_file?.url,
  ];
  for (const c of candidates) {
    const s = String(c || "").trim();
    if (s.startsWith("http")) return s;
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const expectedToken = mustEnv("TGIS_WEBHOOK_SECRET");
    const token = getWebhookToken(req);
    if (!token || token !== expectedToken) return json({ success: false, error: "forbidden" }, 403);

    const service = createClient(mustEnv("SUPABASE_URL"), mustEnv("SUPABASE_SERVICE_ROLE_KEY"));
    const payload = await req.json().catch(() => ({}));
    const requestId = extractRequestId(payload);
    if (!requestId) return json({ success: false, error: "missing_request_id" }, 400);

    const status = normalizeStatus(payload?.status || payload?.event_type || payload?.event);
    const loraUrl = extractLoraUrl(payload);

    const { data: runRows, error: runErr } = await service
      .from("tgis_training_runs")
      .select("id,cluster_id,target_version,status")
      .eq("fal_request_id", requestId)
      .order("id", { ascending: false })
      .limit(1);
    if (runErr) throw new Error(runErr.message);
    const run = Array.isArray(runRows) && runRows[0] ? runRows[0] as any : null;
    if (!run) return json({ success: true, ignored: true, reason: "run_not_found" });

    const runId = Number(run.id);
    const clusterId = run.cluster_id == null ? null : Number(run.cluster_id);
    const targetVersion = String(run.target_version || "").trim();
    const runStatus = String(run.status || "").trim().toLowerCase();
    if (runStatus !== "running") {
      return json({ success: true, ignored: true, reason: `run_status_${runStatus}` });
    }

    if (status === "success") {
      if (!loraUrl) {
        await service
          .from("tgis_training_runs")
          .update({
            status: "failed",
            ended_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            error_text: "webhook_success_without_lora_url",
            webhook_payload_json: payload,
          })
          .eq("id", runId);
        return json({ success: false, error: "missing_lora_url_on_success" }, 400);
      }

      await service
        .from("tgis_training_runs")
        .update({
          status: "success",
          output_lora_url: loraUrl,
          ended_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error_text: null,
          webhook_payload_json: payload,
        })
        .eq("id", runId);

      if (Number.isFinite(clusterId) && targetVersion) {
        const { error: modelErr } = await service
          .from("tgis_model_versions")
          .upsert(
            {
              cluster_id: clusterId,
              version: targetVersion,
              lora_fal_path: loraUrl,
              artifact_uri: loraUrl,
              status: "candidate",
              updated_at: new Date().toISOString(),
            },
            { onConflict: "cluster_id,version" },
          );
        if (modelErr) throw new Error(modelErr.message);
      }
    } else {
      await service
        .from("tgis_training_runs")
        .update({
          status: "failed",
          ended_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error_text: String(payload?.error || payload?.message || "fal_training_failed"),
          webhook_payload_json: payload,
        })
        .eq("id", runId);
    }

    return json({
      success: true,
      request_id: requestId,
      run_id: runId,
      status,
      lora_url: loraUrl,
    });
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
