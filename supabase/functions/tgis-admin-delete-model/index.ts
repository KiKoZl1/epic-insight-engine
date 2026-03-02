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
    const clusterId = Number(body?.clusterId);
    const version = String(body?.version || "").trim();
    if (!Number.isFinite(clusterId) || !version) return json({ success: false, error: "missing_cluster_or_version" }, 400);

    const { data: rows, error: selErr } = await service
      .from("tgis_model_versions")
      .select("cluster_id,version,status")
      .eq("cluster_id", clusterId)
      .eq("version", version)
      .limit(1);
    if (selErr) throw new Error(selErr.message);
    const row = Array.isArray(rows) && rows[0] ? rows[0] as any : null;
    if (!row) return json({ success: false, error: "model_not_found" }, 404);
    if (String(row.status || "") === "active") {
      return json({ success: false, error: "active_model_cannot_be_deleted" }, 409);
    }

    const { error: delErr } = await service
      .from("tgis_model_versions")
      .delete()
      .eq("cluster_id", clusterId)
      .eq("version", version);
    if (delErr) throw new Error(delErr.message);

    return json({ success: true, deleted: { cluster_id: clusterId, version } });
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

