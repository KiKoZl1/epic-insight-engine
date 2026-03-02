import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function mustEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function extractBearer(req: Request): string {
  const authHeader = (req.headers.get("Authorization") || req.headers.get("authorization") || "").trim();
  return authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4;
    if (pad) b64 += "=".repeat(4 - pad);
    const payload = JSON.parse(atob(b64));
    return payload && typeof payload === "object" ? (payload as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

async function resolveAuth(req: Request, serviceClient: ReturnType<typeof createClient>) {
  const serviceKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
  const bearer = extractBearer(req);
  const apiKey = (req.headers.get("apikey") || "").trim();
  if ((bearer && bearer === serviceKey) || (apiKey && apiKey === serviceKey)) {
    return { allowed: true, userId: null as string | null };
  }
  const bearerPayload = bearer ? decodeJwtPayload(bearer) : null;
  const apiPayload = apiKey ? decodeJwtPayload(apiKey) : null;
  if (String(bearerPayload?.role || "") === "service_role") {
    return { allowed: true, userId: null as string | null };
  }
  if (String(apiPayload?.role || "") === "service_role") {
    return { allowed: true, userId: null as string | null };
  }
  if (!bearer) return { allowed: false, userId: null as string | null };

  const authClient = createClient(mustEnv("SUPABASE_URL"), mustEnv("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
  });
  const { data: userRes, error: userErr } = await authClient.auth.getUser();
  if (userErr || !userRes.user?.id) return { allowed: false, userId: null as string | null };

  const { data: roleRows, error: roleErr } = await serviceClient
    .from("user_roles")
    .select("role")
    .eq("user_id", userRes.user.id)
    .limit(1);
  if (roleErr || !Array.isArray(roleRows) || roleRows.length === 0) return { allowed: false, userId: userRes.user.id };
  const role = String(roleRows[0]?.role || "");
  return { allowed: role === "admin" || role === "editor", userId: userRes.user.id };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const service = createClient(mustEnv("SUPABASE_URL"), mustEnv("SUPABASE_SERVICE_ROLE_KEY"));
    const auth = await resolveAuth(req, service);
    if (!auth.allowed) return json({ success: false, error: "forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    const runId = Number(body?.runId);
    const action = String(body?.action || "").trim().toLowerCase();
    if (!Number.isFinite(runId)) return json({ success: false, error: "invalid_runId" }, 400);
    if (!["cancel", "delete"].includes(action)) return json({ success: false, error: "invalid_action" }, 400);

    const { data: runRows, error: runErr } = await service
      .from("tgis_training_runs")
      .select("id,status,cluster_id,target_version,fal_request_id")
      .eq("id", runId)
      .limit(1);
    if (runErr) throw new Error(runErr.message);
    const run = Array.isArray(runRows) && runRows[0] ? runRows[0] as any : null;
    if (!run) return json({ success: false, error: "run_not_found" }, 404);

    const status = String(run.status || "");
    if (action === "cancel") {
      if (["success", "failed", "cancelled"].includes(status)) {
        return json({ success: true, action, run_id: runId, status, note: "already_terminal" });
      }
      const nowIso = new Date().toISOString();
      const { error: updErr } = await service
        .from("tgis_training_runs")
        .update({
          status: "cancelled",
          provider_status: "CANCELLED_BY_ADMIN",
          ended_at: nowIso,
          updated_at: nowIso,
          error_text: "cancelled_by_admin",
        })
        .eq("id", runId);
      if (updErr) throw new Error(updErr.message);
      return json({ success: true, action, run_id: runId, status: "cancelled" });
    }

    if (status === "running") {
      return json({ success: false, error: "cannot_delete_running_use_cancel_first" }, 409);
    }
    const { error: delErr } = await service
      .from("tgis_training_runs")
      .delete()
      .eq("id", runId);
    if (delErr) throw new Error(delErr.message);
    return json({ success: true, action, run_id: runId, deleted: true });
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

