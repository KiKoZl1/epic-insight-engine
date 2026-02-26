import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

function json(res: unknown, status = 200) {
  return new Response(JSON.stringify(res), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function mustEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

function clampInt(value: unknown, fallback: number, min: number, max: number): number {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(n)));
}

function isServiceRoleRequest(req: Request, serviceKey: string): boolean {
  const authHeader = (req.headers.get("Authorization") || "").trim();
  const apiKeyHeader = (req.headers.get("apikey") || "").trim();
  const authToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : authHeader;
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const expectedRef = (() => {
    try {
      const host = new URL(supabaseUrl).hostname || "";
      const [ref] = host.split(".");
      return ref || null;
    } catch {
      return null;
    }
  })();

  const decodeJwtPayload = (token: string): Record<string, unknown> | null => {
    try {
      const parts = token.split(".");
      if (parts.length !== 3) return null;
      let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const pad = b64.length % 4;
      if (pad) b64 += "=".repeat(4 - pad);
      const payload = JSON.parse(atob(b64));
      return payload && typeof payload === "object" ? payload as Record<string, unknown> : null;
    } catch {
      return null;
    }
  };

  const isServiceRoleJwt = (token: string): boolean => {
    const payload = decodeJwtPayload(token);
    if (!payload) return false;
    if (String(payload.role || "") !== "service_role") return false;
    if (!expectedRef) return true;
    return String(payload.ref || "") === expectedRef;
  };

  if (
    serviceKey &&
    (authHeader === `Bearer ${serviceKey}` || authHeader === serviceKey || apiKeyHeader === serviceKey)
  ) {
    return true;
  }

  return isServiceRoleJwt(authToken) || isServiceRoleJwt(apiKeyHeader);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const serviceKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
    if (!isServiceRoleRequest(req, serviceKey)) {
      return json({ success: false, error: "forbidden" }, 403);
    }

    const supabase = createClient(mustEnv("SUPABASE_URL"), serviceKey);

    let body: any = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const defaultRegions = ["NAE", "EU", "BR", "ASIA"];
    const regions = Array.isArray(body?.regions)
      ? body.regions.map((r: unknown) => String(r || "").trim()).filter(Boolean)
      : [String(body?.region || "").trim()].filter(Boolean);
    const regionList = regions.length ? regions : defaultRegions;

    const surfaceName = String(body?.surfaceName || "CreativeDiscoverySurface_Frontend").trim();
    const windowDays = clampInt(body?.windowDays, 14, 1, 60);
    const batchTargets = clampInt(body?.batchTargets, 8, 1, 64);
    const activeWithinHours = clampInt(body?.activeWithinHours, 6, 1, 48);
    const maxPanelsPerTarget = clampInt(body?.maxPanelsPerTarget, 24, 1, 80);

    const activeAfterIso = new Date(Date.now() - activeWithinHours * 3600_000).toISOString();

    const { data: targetRows, error: targetErr } = await supabase
      .from("discovery_exposure_targets")
      .select("id,region,surface_name,last_ok_tick_at")
      .eq("surface_name", surfaceName)
      .in("region", regionList)
      .not("last_ok_tick_at", "is", null)
      .gte("last_ok_tick_at", activeAfterIso)
      .order("last_ok_tick_at", { ascending: false, nullsFirst: false })
      .limit(batchTargets);

    if (targetErr) throw new Error(targetErr.message);

    const targets = (targetRows || []) as Array<{ id: string; region: string; surface_name: string; last_ok_tick_at: string }>;

    let processedTargets = 0;
    let processedPanels = 0;
    const errors: Array<{ targetId: string; panelName: string | null; error: string }> = [];

    for (const target of targets) {
      const fromIso = new Date(Date.now() - windowDays * 24 * 3600_000).toISOString();
      const { data: panelRows, error: panelErr } = await supabase
        .from("discovery_exposure_presence_segments")
        .select("panel_name")
        .eq("target_id", target.id)
        .eq("link_code_type", "island")
        .gte("start_ts", fromIso)
        .order("start_ts", { ascending: false })
        .limit(5000);

      if (panelErr) {
        errors.push({ targetId: target.id, panelName: null, error: panelErr.message || "panel query failed" });
        continue;
      }

      const panelNames = Array.from(
        new Set(
          (panelRows || [])
            .map((r: any) => String(r?.panel_name || "").trim())
            .filter(Boolean),
        ),
      ).slice(0, maxPanelsPerTarget);

      if (panelNames.length === 0) {
        continue;
      }

      let okForTarget = 0;
      for (const panelName of panelNames) {
        const { error } = await supabase.rpc("compute_discovery_panel_intel_snapshot", {
          p_target_id: target.id,
          p_window_days: windowDays,
          p_panel_name: panelName,
        });

        if (error) {
          errors.push({ targetId: target.id, panelName, error: error.message || "unknown" });
          continue;
        }

        okForTarget += 1;
        processedPanels += 1;
      }

      if (okForTarget > 0) {
        processedTargets += 1;
      }
    }

    return json({
      success: true,
      region_scope: regionList,
      surfaceName,
      windowDays,
      batchTargets,
      activeWithinHours,
      maxPanelsPerTarget,
      processed_targets: processedTargets,
      processed_panels: processedPanels,
      errors,
    });
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
