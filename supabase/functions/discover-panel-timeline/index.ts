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

function floorToHour(date: Date): Date {
  const d = new Date(date);
  d.setUTCMinutes(0, 0, 0);
  return d;
}

function addHours(date: Date, h: number): Date {
  return new Date(date.getTime() + h * 3600_000);
}

function isTechnicalToken(code: string): boolean {
  const c = String(code || "").toLowerCase();
  return c.startsWith("reference_") || c.startsWith("ref_panel_");
}

function overlapMinutes(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): number {
  const start = Math.max(aStart.getTime(), bStart.getTime());
  const end = Math.min(aEnd.getTime(), bEnd.getTime());
  if (end <= start) return 0;
  return (end - start) / 60000;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabase = createClient(mustEnv("SUPABASE_URL"), mustEnv("SUPABASE_SERVICE_ROLE_KEY"));

    let body: any = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const region = String(body.region || "NAE");
    const surfaceName = String(body.surfaceName || "CreativeDiscoverySurface_Frontend");
    const panelName = String(body.panelName || "").trim();
    const hours = Math.max(1, Math.min(168, Number(body.hours ?? 24)));

    if (!panelName) return json({ success: false, error: "Missing panelName" }, 400);

    const { data: targetRows, error: tErr } = await supabase
      .from("discovery_exposure_targets")
      .select("id,region,surface_name,last_ok_tick_at")
      .eq("region", region)
      .eq("surface_name", surfaceName)
      .order("last_ok_tick_at", { ascending: false, nullsFirst: false })
      .limit(1);
    if (tErr) throw new Error(tErr.message);
    if (!targetRows || targetRows.length === 0) {
      return json({ success: false, error: "target not found" }, 404);
    }

    const target = targetRows[0] as any;
    const targetId = String(target.id);

    const to = new Date();
    const from = new Date(to.getTime() - hours * 3600_000);

    const { data: segs, error: sErr } = await supabase
      .from("discovery_exposure_rank_segments")
      .select("link_code,start_ts,end_ts,last_seen_ts,ccu_max,ccu_start,ccu_end")
      .eq("target_id", targetId)
      .eq("panel_name", panelName)
      .lt("start_ts", to.toISOString())
      .or(`end_ts.is.null,end_ts.gt.${from.toISOString()}`)
      .order("start_ts", { ascending: true })
      .limit(50000);
    if (sErr) throw new Error(sErr.message);

    const rows = (segs || []) as any[];

    const bucketStart = floorToHour(from);
    const bucketEndExclusive = addHours(floorToHour(to), 1);

    const buckets = new Map<string, {
      ts: string;
      ccuWeighted: number;
      minutes_exposed: number;
      activeSet: Set<string>;
      itemsMinutes: Map<string, number>;
    }>();

    for (let cursor = new Date(bucketStart); cursor < bucketEndExclusive; cursor = addHours(cursor, 1)) {
      buckets.set(cursor.toISOString(), {
        ts: cursor.toISOString(),
        ccuWeighted: 0,
        minutes_exposed: 0,
        activeSet: new Set<string>(),
        itemsMinutes: new Map<string, number>(),
      });
    }

    for (const seg of rows) {
      const segStart = new Date(String(seg.start_ts));
      const segEnd = new Date(String(seg.end_ts || seg.last_seen_ts || to.toISOString()));
      if (!(segStart < segEnd)) continue;

      for (let cursor = new Date(bucketStart); cursor < bucketEndExclusive; cursor = addHours(cursor, 1)) {
        const bStart = cursor;
        const bEnd = addHours(cursor, 1);
        const mins = overlapMinutes(segStart, segEnd, bStart, bEnd);
        if (mins <= 0) continue;

        const key = bStart.toISOString();
        const bucket = buckets.get(key);
        if (!bucket) continue;

        const linkCode = String(seg.link_code || "");
        const ccu = Number(seg.ccu_end ?? seg.ccu_max ?? seg.ccu_start ?? 0) || 0;

        bucket.minutes_exposed += mins;
        bucket.ccuWeighted += ccu * (mins / 60);
        if (linkCode) {
          bucket.activeSet.add(linkCode);
          bucket.itemsMinutes.set(linkCode, (bucket.itemsMinutes.get(linkCode) || 0) + mins);
        }
      }
    }

    const series = Array.from(buckets.values())
      .map((b) => {
        const activeItems = b.activeSet.size;
        return {
          ts: b.ts,
          ccu: Number(b.ccuWeighted.toFixed(2)),
          minutes_exposed: Number(b.minutes_exposed.toFixed(2)),
          active_items: activeItems,
        };
      })
      .filter((p) => p.ts >= from.toISOString() && p.ts <= to.toISOString())
      .sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());

    const totalByCode = new Map<string, number>();
    for (const b of buckets.values()) {
      for (const [code, mins] of b.itemsMinutes.entries()) {
        totalByCode.set(code, (totalByCode.get(code) || 0) + mins);
      }
    }

    const sampleCodes = Array.from(totalByCode.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([code]) => code);

    const metaMap = new Map<string, any>();
    if (sampleCodes.length) {
      const { data: metaRows, error: mErr } = await supabase
        .from("discover_link_metadata")
        .select("link_code,title,image_url,support_code")
        .in("link_code", sampleCodes);
      if (!mErr) {
        for (const row of metaRows || []) {
          metaMap.set(String((row as any).link_code), row as any);
        }
      }
    }

    const sampleTopItems = sampleCodes.map((code) => {
      const m = metaMap.get(code) || null;
      const fallbackTitle = isTechnicalToken(code) ? "Unknown item" : code;
      return {
        link_code: code,
        title: m?.title ?? fallbackTitle,
        image_url: m?.image_url ?? null,
        creator_code: m?.support_code ?? null,
        minutes_exposed: Number((totalByCode.get(code) || 0).toFixed(2)),
      };
    });

    return json({
      success: true,
      region,
      surfaceName,
      panelName,
      targetId,
      from: from.toISOString(),
      to: to.toISOString(),
      hours,
      series,
      sample_top_items: sampleTopItems,
    });
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
