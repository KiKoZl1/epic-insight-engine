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

async function requireAdminOrEditor(req: Request, supabase: any): Promise<string> {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length) : "";
  if (!token) throw new Error("forbidden");

  const { data: u, error: uErr } = await supabase.auth.getUser(token);
  if (uErr || !u?.user?.id) throw new Error("forbidden");
  const userId = u.user.id;

  const { data: roles, error: rErr } = await supabase
    .from("user_roles")
    .select("role")
    .eq("user_id", userId)
    .in("role", ["admin", "editor"])
    .limit(1);
  if (rErr || !roles || roles.length === 0) throw new Error("forbidden");
  return userId;
}

function toDate(d: string | Date): string {
  const x = typeof d === "string" ? new Date(d) : d;
  return x.toISOString().slice(0, 10);
}

function normalizeRpcJson<T = Record<string, unknown>>(input: unknown): T {
  if (Array.isArray(input)) {
    if (input.length === 0) return {} as T;
    return normalizeRpcJson<T>(input[0]);
  }
  if (typeof input === "string") {
    try {
      return normalizeRpcJson<T>(JSON.parse(input));
    } catch {
      return {} as T;
    }
  }
  if (input && typeof input === "object") return input as T;
  return {} as T;
}

function isServiceRoleRequest(req: Request, serviceKey: string): boolean {
  const authHeader = (req.headers.get("Authorization") || "").trim();
  const apiKeyHeader = (req.headers.get("apikey") || "").trim();
  const authToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : authHeader;

  const isServiceRoleJwt = (token: string): boolean => {
    try {
      const parts = token.split(".");
      if (parts.length !== 3) return false;
      let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const pad = b64.length % 4;
      if (pad) b64 += "=".repeat(4 - pad);
      const payload = JSON.parse(atob(b64));
      return payload?.role === "service_role";
    } catch {
      return false;
    }
  };

  if (serviceKey && (
    authHeader === `Bearer ${serviceKey}` ||
    authHeader === serviceKey ||
    apiKeyHeader === serviceKey
  )) return true;

  return isServiceRoleJwt(authToken) || isServiceRoleJwt(apiKeyHeader);
}

const EPIC_CREATOR_KEYS = new Set(["epic", "epic games", "epic labs", "fortnite"]);
const PUBLIC_CATEGORY_KEYS = new Set([
  "fortnite ugc",
  "lego",
  "tmnt",
  "fall guys",
  "squid game",
  "rocket racing",
  "kpop demon hunters",
  "the walking dead universe",
]);
const PARTNER_CODENAME_LABELS: Record<string, string> = {
  perfectkiwi: "Projeto Perfect Kiwi",
  "perfect kiwi": "Projeto Perfect Kiwi",
  "fortnite secret partner": "Projeto Secret Partner",
  "secret partner": "Projeto Secret Partner",
};

function normalizeCreator(v: unknown): string {
  return String(v || "").trim().toLowerCase();
}

function isEpicCreator(v: unknown): boolean {
  const n = normalizeCreator(v);
  if (!n) return false;
  if (EPIC_CREATOR_KEYS.has(n)) return true;
  return n.includes("epic");
}

function extractCreator(item: any): string {
  return String(
    item?.creator ??
    item?.creator_code ??
    item?.support_code ??
    item?.name ??
    ""
  );
}

function filterNonEpicItems(items: any[]): any[] {
  return (items || []).filter((i: any) => !isEpicCreator(extractCreator(i)));
}

function sanitizeRankingsExcludeEpic(rankings: any): any {
  const keysToFilter = [
    "topUniquePlayers", "topTotalPlays", "topMinutesPlayed", "topAvgMinutesPerPlayer",
    "topRetentionD1", "topRetentionD7", "topPlaysPerPlayer", "topFavsPer100",
    "topRecPer100", "topFavsPerPlay", "topRecsPerPlay", "topStickinessD1",
    "topStickinessD7", "topStickinessD1_UGC", "topStickinessD7_UGC",
    "topRetentionAdjD1", "topRetentionAdjD7", "failedIslandsList", "revivedIslands",
    "deadIslands", "topWeeklyGrowth", "topRisers", "topDecliners",
    "topNewIslandsByPlays", "topNewIslandsByPlaysPublished", "topNewIslandsByCCU",
    "mostUpdatedIslandsThisWeek", "mostUpdatedIslandsWeekly", "topCreatorsByPlays", "topCreatorsByPlayers",
    "topCreatorsByMinutes", "topCreatorsByCCU", "creatorRisers", "creatorDecliners",
    "creatorRankClimbers",
  ];
  for (const key of keysToFilter) {
    if (Array.isArray(rankings?.[key])) {
      rankings[key] = filterNonEpicItems(rankings[key]);
    }
  }
  // Keep only UGC list in this key as well.
  if (Array.isArray(rankings?.topPeakCCU_UGC)) {
    rankings.topPeakCCU_UGC = filterNonEpicItems(rankings.topPeakCCU_UGC);
  }
  return rankings;
}

function buildEpicSpotlight(rankings: any): any {
  const topPeak = (rankings?.topPeakCCU || []).filter((i: any) => isEpicCreator(extractCreator(i))).slice(0, 10);
  const topPlays = (rankings?.topTotalPlays || []).filter((i: any) => isEpicCreator(extractCreator(i))).slice(0, 10);
  const topUnique = (rankings?.topUniquePlayers || []).filter((i: any) => isEpicCreator(extractCreator(i))).slice(0, 10);
  const risers = (rankings?.topRisers || []).filter((i: any) => isEpicCreator(extractCreator(i))).slice(0, 10);
  const decliners = (rankings?.topDecliners || []).filter((i: any) => isEpicCreator(extractCreator(i))).slice(0, 10);
  return {
    topPeakCCU: topPeak,
    topByPlays: topPlays,
    topByUniquePlayers: topUnique,
    risers,
    decliners,
  };
}

function normalizeCategoryKey(v: unknown): string {
  return String(v || "").trim().toLowerCase();
}

function titleCaseWords(v: string): string {
  return v
    .split(" ")
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

function isLikelyPartnerCodename(categoryKey: string): boolean {
  if (!categoryKey) return false;
  if (PUBLIC_CATEGORY_KEYS.has(categoryKey)) return false;
  if (PARTNER_CODENAME_LABELS[categoryKey]) return true;
  if (categoryKey.includes("secret partner")) return true;

  const words = categoryKey.split(/\s+/).filter(Boolean);
  const compact = categoryKey.replace(/[^a-z0-9]/g, "");
  if (words.length > 2) return false;
  if (compact.length < 8) return false;
  if (!/^[a-z0-9 _-]+$/.test(categoryKey)) return false;
  return true;
}

function partnerProjectName(categoryKey: string): string {
  if (PARTNER_CODENAME_LABELS[categoryKey]) return PARTNER_CODENAME_LABELS[categoryKey];
  const cleaned = categoryKey.replace(/[_-]+/g, " ");
  return `Projeto ${titleCaseWords(cleaned)}`.trim();
}

async function buildPartnerSignals(supabase: any, reportId: string): Promise<any[]> {
  const pageSize = 5000;
  const maxRows = 1000000;
  const agg = new Map<string, { codename: string; islands: number; plays: number; players: number; minutes: number }>();
  let totalPlays = 0;

  for (let offset = 0; offset < maxRows; offset += pageSize) {
    const { data, error } = await supabase
      .from("discover_report_islands")
      .select("category,week_plays,week_unique,week_minutes")
      .eq("report_id", reportId)
      .range(offset, offset + pageSize - 1);
    if (error) throw new Error(error.message);
    const rows = data || [];
    if (rows.length === 0) break;

    for (const row of rows) {
      const plays = Number((row as any).week_plays || 0);
      totalPlays += plays;

      const categoryRaw = String((row as any).category || "").trim();
      const categoryKey = normalizeCategoryKey(categoryRaw);
      if (!isLikelyPartnerCodename(categoryKey)) continue;

      const entry = agg.get(categoryKey) || {
        codename: categoryRaw || categoryKey,
        islands: 0,
        plays: 0,
        players: 0,
        minutes: 0,
      };
      entry.islands += 1;
      entry.plays += plays;
      entry.players += Number((row as any).week_unique || 0);
      entry.minutes += Number((row as any).week_minutes || 0);
      if (!entry.codename && categoryRaw) entry.codename = categoryRaw;
      agg.set(categoryKey, entry);
    }

    if (rows.length < pageSize) break;
  }

  return Array.from(agg.entries())
    .map(([key, v]) => ({
      codename: v.codename || key,
      projectName: partnerProjectName(key),
      islands: v.islands,
      plays: v.plays,
      players: v.players,
      minutes: v.minutes,
      sharePlaysPct: totalPlays > 0 ? Number(((v.plays / totalPlays) * 100).toFixed(2)) : 0,
      classification: "internal_codename_candidate",
    }))
    .sort((a, b) => b.plays - a.plays)
    .slice(0, 12);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const serviceRoleKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createClient(mustEnv("SUPABASE_URL"), serviceRoleKey);
    const serviceRoleMode = isServiceRoleRequest(req, serviceRoleKey);
    const userId = serviceRoleMode ? null : await requireAdminOrEditor(req, supabase);

    let body: any = {};
    try { body = await req.json(); } catch { body = {}; }

    const weeklyReportId = body.weeklyReportId ? String(body.weeklyReportId) : null;
    const reportIdIn = body.reportId ? String(body.reportId) : null;
    const runAi = body.runAi != null ? Boolean(body.runAi) : true;
    const reinjectExposure = body.reinjectExposure != null ? Boolean(body.reinjectExposure) : true;
    const refreshMetadata = body.refreshMetadata != null ? Boolean(body.refreshMetadata) : false;
    const buildEvidence = body.buildEvidence != null ? Boolean(body.buildEvidence) : true;
    const evidenceOnly = body.evidenceOnly != null ? Boolean(body.evidenceOnly) : false;

    if (!weeklyReportId && !reportIdIn) return json({ success: false, error: "Missing weeklyReportId or reportId" }, 400);

    // â”€â”€ Resolve report & weekly report â”€â”€
    let reportId = reportIdIn;
    let wrRow: any = null;
    if (weeklyReportId) {
      const { data, error } = await supabase
        .from("weekly_reports")
        .select("id,discover_report_id,date_from,date_to,rankings_json")
        .eq("id", weeklyReportId)
        .single();
      if (error || !data) return json({ success: false, error: "weekly report not found" }, 404);
      wrRow = data;
      reportId = String(data.discover_report_id || "");
      if (!reportId) return json({ success: false, error: "weekly report missing discover_report_id" }, 400);
    }

    const { data: report, error: rErr } = await supabase
      .from("discover_reports")
      .select("id,week_start,week_end,week_number,year")
      .eq("id", reportId!)
      .single();
    if (rErr || !report) return json({ success: false, error: "discover report not found" }, 404);

    const weekStartDate = toDate(report.week_start);
    const weekEndDate = toDate(report.week_end);

    // â”€â”€ Find previous report for WoW baselines â”€â”€
    const { data: prev } = await supabase
      .from("discover_reports")
      .select("id")
      .eq("phase", "done")
      .lt("week_end", report.week_start)
      .order("week_end", { ascending: false })
      .limit(1)
      .maybeSingle();
    const prevReportId = prev?.id ? String(prev.id) : null;

    if (evidenceOnly) {
      if (!weeklyReportId) return json({ success: false, error: "evidenceOnly requires weeklyReportId" }, 400);

      const { data: wrExisting, error: wrErr } = await supabase
        .from("weekly_reports")
        .select("id,rebuild_count,rankings_json")
        .eq("id", weeklyReportId)
        .single();
      if (wrErr || !wrExisting) return json({ success: false, error: wrErr?.message || "weekly report not found" }, 404);

      const existingRankings = ((wrExisting as any).rankings_json || {}) as any;
      const topNewItems: any[] = Array.isArray(existingRankings.topNewIslandsByPlaysPublished)
        ? existingRankings.topNewIslandsByPlaysPublished
        : (Array.isArray(existingRankings.topNewIslandsByPlays) ? existingRankings.topNewIslandsByPlays : []);
      const mostUpdatedItems: any[] = Array.isArray(existingRankings.mostUpdatedIslandsThisWeek)
        ? existingRankings.mostUpdatedIslandsThisWeek
        : [];

      const [covRes, histRes, expCovRes, topPanelsRes, breadthRes] = await Promise.all([
        supabase.rpc("report_link_metadata_coverage", { p_report_id: reportId }),
        supabase.rpc("report_low_perf_histogram", { p_report_id: reportId }),
        supabase.rpc("report_exposure_coverage", { p_weekly_report_id: weeklyReportId }),
        supabase.rpc("discovery_exposure_top_panels", { p_date_from: weekStartDate, p_date_to: weekEndDate, p_limit: 20 }),
        supabase.rpc("discovery_exposure_breadth_top", { p_date_from: weekStartDate, p_date_to: weekEndDate, p_limit: 20 }),
      ]);

      const evidence = {
        dataQuality: {
          baselineAvailable: Boolean(prevReportId),
          metadataCoverage: covRes.data || null,
          exposureCoverage: expCovRes.data || null,
          lowPerformanceHistogram: histRes.data || null,
        },
        newIslands: { topByPlays: topNewItems.slice(0, 20), topByPlayers: topNewItems.slice(0, 20) },
        updates: { mostUpdated: mostUpdatedItems.slice(0, 20) },
        exposure: {
          topPanelsByMinutes: topPanelsRes.data || [],
          breadthTop: breadthRes.data || [],
          hasDiscoveryExposure: true,
        },
      };

      const mergedRankings: any = { ...existingRankings, evidence };

      const { data: pollutionRows } = await supabase
        .from("discovery_public_pollution_creators_now")
        .select("*")
        .order("spam_score", { ascending: false })
        .limit(30);
      if (pollutionRows && pollutionRows.length > 0) {
        mergedRankings.discoveryPollution = pollutionRows.map((r: any) => ({
          creator_code: r.creator_code,
          spam_score: r.spam_score,
          duplicate_clusters_7d: r.duplicate_clusters_7d,
          duplicate_islands_7d: r.duplicate_islands_7d,
          duplicates_over_min: r.duplicates_over_min,
          sample_titles: r.sample_titles || [],
          as_of: r.as_of,
        }));
      }

      const { error: updErr } = await supabase
        .from("weekly_reports")
        .update({
          rankings_json: mergedRankings,
          rebuild_count: Number((wrExisting as any).rebuild_count || 0) + 1,
          last_rebuilt_at: new Date().toISOString(),
        })
        .eq("id", weeklyReportId);
      if (updErr) throw new Error(updErr.message);

      return json({
        success: true,
        evidenceOnly: true,
        reportId,
        weeklyReportId,
        baselineAvailable: Boolean(prevReportId),
      });
    }

    // â”€â”€ Optional: refresh metadata for top exposure items â”€â”€
    if (refreshMetadata && wrRow?.rankings_json?.discoveryExposure?.topByPanel) {
      const topByPanel = Array.isArray(wrRow.rankings_json.discoveryExposure.topByPanel)
        ? wrRow.rankings_json.discoveryExposure.topByPanel : [];
      const codes = Array.from(new Set(topByPanel.map((r: any) => String(r.linkCode)).filter(Boolean))).slice(0, 500);
      if (codes.length) {
        await supabase.functions.invoke("discover-links-metadata-collector", {
          body: { mode: "refresh_link_codes", linkCodes: codes },
        });
      }
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // CORE: Call ALL finalize RPCs in parallel (same as collector)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    console.log(`[rebuild] Starting finalize RPC waves for report ${reportId}`);

    const [
      kpisRes,
      rankingsRes,
      creatorsRes,
      categoriesRes,
      distributionsRes,
      trendingRes,
    ] = await Promise.all([
      supabase.rpc("report_finalize_kpis", { p_report_id: reportId, p_prev_report_id: prevReportId }),
      supabase.rpc("report_finalize_rankings", { p_report_id: reportId, p_limit: 10 }),
      supabase.rpc("report_finalize_creators", { p_report_id: reportId, p_limit: 10 }),
      supabase.rpc("report_finalize_categories", { p_report_id: reportId, p_limit: 15 }),
      supabase.rpc("report_finalize_distributions", { p_report_id: reportId }),
      supabase.rpc("report_finalize_trending", { p_report_id: reportId, p_min_islands: 5, p_limit: 20 }),
    ]);

    const [newIslandsRes, updatedRes, toolSplitRes, rookiesRes, versionEnrichmentRes] = await Promise.all([
      supabase.rpc("report_new_islands_by_launch", { p_report_id: reportId, p_week_start: weekStartDate, p_week_end: weekEndDate, p_limit: 50 }),
      supabase.rpc("report_most_updated_islands", { p_report_id: reportId, p_week_start: weekStartDate, p_week_end: weekEndDate, p_limit: 50 }),
      supabase.rpc("report_finalize_tool_split", { p_report_id: reportId }),
      supabase.rpc("report_finalize_rookies", { p_report_id: reportId, p_limit: 10 }),
      supabase.rpc("report_version_enrichment", { p_report_id: reportId }),
    ]);

    const [exposureAnalysisRes, exposureEfficiencyRes] = await Promise.all([
      supabase.rpc("report_finalize_exposure_analysis", { p_report_id: reportId!, p_days: 7 }),
      supabase.rpc("report_finalize_exposure_efficiency", { p_report_id: reportId!, p_limit: 15 }),
    ]);

    const [moversRes, categoryMoversRes, creatorMoversRes] = prevReportId
      ? await Promise.all([
          supabase.rpc("report_finalize_wow_movers", { p_report_id: reportId, p_prev_report_id: prevReportId, p_limit: 10 }),
          supabase.rpc("report_finalize_category_movers", { p_report_id: reportId, p_prev_report_id: prevReportId, p_limit: 10 }),
          supabase.rpc("report_finalize_creator_movers", { p_report_id: reportId, p_prev_report_id: prevReportId, p_limit: 10 }),
        ])
      : [
          { data: { topRisers: [], topDecliners: [] }, error: null },
          { data: { categoryRisers: [], categoryDecliners: [] }, error: null },
          { data: { creatorRisers: [], creatorDecliners: [], creatorRankClimbers: [] }, error: null },
        ];

    const kpisData = normalizeRpcJson<any>(kpisRes.data);
    const rankingsData = normalizeRpcJson<any>(rankingsRes.data);
    const creatorsData = normalizeRpcJson<any>(creatorsRes.data);
    const categoriesData = normalizeRpcJson<any>(categoriesRes.data);
    const distributionsData = normalizeRpcJson<any>(distributionsRes.data);
    const trendingData = normalizeRpcJson<any>(trendingRes.data);
    const moversData = normalizeRpcJson<any>(moversRes.data);
    const toolSplitData = normalizeRpcJson<any>(toolSplitRes.data);
    const rookiesData = normalizeRpcJson<any>(rookiesRes.data);
    const exposureAnalysisData = normalizeRpcJson<any>(exposureAnalysisRes.data);
    const exposureEfficiencyData = normalizeRpcJson<any>(exposureEfficiencyRes.data);
    const categoryMoversData = normalizeRpcJson<any>(categoryMoversRes.data);
    const creatorMoversData = normalizeRpcJson<any>(creatorMoversRes.data);
    const versionEnrichmentData = normalizeRpcJson<any>(versionEnrichmentRes.data);

        // Fail-fast: do not persist partial report payloads.
    const rpcFailures = (
      [
        ["kpis", kpisRes], ["rankings", rankingsRes], ["creators", creatorsRes],
        ["categories", categoriesRes], ["distributions", distributionsRes],
        ["trending", trendingRes], ["movers", moversRes],
        ["toolSplit", toolSplitRes], ["rookies", rookiesRes], ["versionEnrichment", versionEnrichmentRes],
        ["exposureAnalysis", exposureAnalysisRes], ["exposureEfficiency", exposureEfficiencyRes],
        ["categoryMovers", categoryMoversRes], ["creatorMovers", creatorMoversRes],
      ] as const
    ).filter(([_, res]) => Boolean((res as any)?.error));

    if (
      rpcFailures.length > 0 ||
      Object.keys(kpisData).length === 0 ||
      Object.keys(rankingsData).length === 0 ||
      Object.keys(creatorsData).length === 0 ||
      Object.keys(categoriesData).length === 0 ||
      Object.keys(distributionsData).length === 0 ||
      Object.keys(trendingData).length === 0 ||
      Object.keys(toolSplitData).length === 0 ||
      Object.keys(rookiesData).length === 0 ||
      Object.keys(exposureAnalysisData).length === 0 ||
      Object.keys(exposureEfficiencyData).length === 0
    ) {
      const details = rpcFailures
        .map(([name, res]) => `${name}:${(res as any).error?.message || "unknown"}`)
        .join(" | ");
      throw new Error(`[rebuild] critical RPC failure(s): ${details || "empty payload from required RPCs"}`);
    }

    // Assemble KPIs
    const platformKPIs: any = {
      ...kpisData,
      // Authoritative source is report_finalize_kpis (published_at_epic window).
      // Keep field from KPI RPC (fallback to generic weekly new-maps metric).
      newMapsThisWeekPublished:
        kpisData?.newMapsThisWeekPublished != null
          ? Number(kpisData.newMapsThisWeekPublished)
          : (kpisData?.newMapsThisWeek || 0),
      baselineAvailable: Boolean(prevReportId),
    };

    // Assemble Rankings
    const topNewItems: any[] = (newIslandsRes.data || []).map((r: any) => ({
      code: r.island_code, name: r.title || r.island_code, title: r.title,
      creator: r.creator_code, category: r.category || "Fortnite UGC", value: r.week_plays || 0,
    }));

    // Enrich mostUpdated with version (from RPC) and image_url (from cache)
    const updatedRaw = updatedRes.data || [];
    const mostUpdatedItems: any[] = updatedRaw.map((r: any) => ({
      code: r.island_code, name: r.title || r.island_code, title: r.title,
      creator: r.creator_code,
      category: r.category || "Fortnite UGC",
      value: Number(r.version || 0),
      version: r.version || null,
      weekly_updates: Number(r.weekly_updates || 0),
      week_plays: Number(r.week_plays || 0),
      week_unique: Number(r.week_unique || 0),
    }));
    const mostUpdatedWeekly: any[] = [...mostUpdatedItems]
      .sort((a, b) =>
        (b.weekly_updates || 0) - (a.weekly_updates || 0) ||
        (b.version || 0) - (a.version || 0) ||
        (b.week_plays || 0) - (a.week_plays || 0)
      )
      .slice(0, 50)
      .map((i) => ({ ...i, value: Number(i.weekly_updates || 0) }));

    const computedRankings: any = {
      ...rankingsData,
      ...creatorsData,
      ...categoriesData,
      ...distributionsData,
      ...trendingData,
      ...moversData,
      ...toolSplitData,
      ...rookiesData,
      ...exposureAnalysisData,
      ...exposureEfficiencyData,
      ...categoryMoversData,
      ...creatorMoversData,
      topNewIslandsByPlays: topNewItems,
      topNewIslandsByPlaysPublished: topNewItems,
      topNewIslandsByCCU: [...topNewItems].sort((a, b) => (b.value || 0) - (a.value || 0)).slice(0, 10),
      mostUpdatedIslandsThisWeek: mostUpdatedItems,
      mostUpdatedIslandsWeekly: mostUpdatedWeekly,
      versionEnrichment: versionEnrichmentData,
      topAvgPeakCCU: rankingsData.topPeakCCU || [],
      topAvgPeakCCU_UGC: rankingsData.topPeakCCU_UGC || [],
      baselineAvailable: Boolean(prevReportId),
    };

    // Partner signals: internal category codenames (no island names/codes exposed).
    try {
      const partnerSignals = await buildPartnerSignals(supabase, reportId!);
      computedRankings.partnerSignals = partnerSignals;
      computedRankings.partnerSignalsMeta = {
        policy: "No island codes or island names. Aggregated category-level signals only.",
        generatedAt: new Date().toISOString(),
      };
    } catch (e) {
      console.error("[rebuild] partner signals build failed (non-fatal):", e);
      computedRankings.partnerSignals = [];
      computedRankings.partnerSignalsMeta = {
        policy: "No island codes or island names. Aggregated category-level signals only.",
        generatedAt: new Date().toISOString(),
        error: e instanceof Error ? e.message : String(e),
      };
    }

    // Bulk-enrich ALL island ranking items with image_url from cache
    const ISLAND_RANKING_KEYS = [
      "topPeakCCU", "topPeakCCU_UGC", "topUniquePlayers", "topTotalPlays",
      "topMinutesPlayed", "topAvgMinutesPerPlayer", "topRetentionD1", "topRetentionD7",
      "topPlaysPerPlayer", "topFavsPer100", "topRecPer100", "topFavsPerPlay", "topRecsPerPlay",
      "topStickinessD1", "topStickinessD7", "topStickinessD1_UGC", "topStickinessD7_UGC",
      "topRetentionAdjD1", "topRetentionAdjD7",
      "failedIslandsList", "revivedIslands", "deadIslands",
      "topWeeklyGrowth", "topRisers", "topDecliners",
      "topNewIslandsByPlays", "topNewIslandsByPlaysPublished", "topNewIslandsByCCU",
      "mostUpdatedIslandsThisWeek", "mostUpdatedIslandsWeekly",
    ];
    const allCodes = new Set<string>();
    for (const key of ISLAND_RANKING_KEYS) {
      const arr = computedRankings[key];
      if (Array.isArray(arr)) {
        for (const item of arr) {
          const c = item.code || item.island_code;
          if (c) allCodes.add(c);
        }
      }
    }
    const codesArr = Array.from(allCodes);
    const imageMap: Record<string, string> = {};
    if (codesArr.length > 0) {
      // Fetch in batches of 500
      for (let i = 0; i < codesArr.length; i += 500) {
        const batch = codesArr.slice(i, i + 500);
        const { data: cacheRows } = await supabase
          .from("discover_islands_cache")
          .select("island_code, image_url")
          .in("island_code", batch);
        for (const row of (cacheRows || [])) {
          if (row.image_url) imageMap[row.island_code] = row.image_url;
        }
      }
    }
    // Inject image_url into every ranking item
    for (const key of ISLAND_RANKING_KEYS) {
      const arr = computedRankings[key];
      if (Array.isArray(arr)) {
        for (const item of arr) {
          const c = item.code || item.island_code;
          if (c && imageMap[c] && !item.image_url) {
            item.image_url = imageMap[c];
          }
        }
      }
    }

    // Keep global topPeakCCU with Epic, but strip Epic from other UGC-oriented sections.
    const epicSpotlight = buildEpicSpotlight(computedRankings);
    sanitizeRankingsExcludeEpic(computedRankings);
    computedRankings.epicSpotlight = epicSpotlight;

    // â”€â”€ Save to discover_reports â”€â”€
    await supabase.from("discover_reports").update({
      platform_kpis: platformKPIs,
      computed_rankings: computedRankings,
    }).eq("id", reportId!);

    console.log(`[rebuild] RPCs done. KPIs: totalIslands=${platformKPIs.totalIslands}, active=${platformKPIs.activeIslands}, new=${platformKPIs.newMapsThisWeekPublished}`);

    // â”€â”€ Update weekly_reports CMS entry â”€â”€
    if (weeklyReportId) {
      // Build evidence packs in parallel
      if (buildEvidence) {
        const [covRes, histRes, expCovRes, topPanelsRes, breadthRes] = await Promise.all([
          supabase.rpc("report_link_metadata_coverage", { p_report_id: reportId }),
          supabase.rpc("report_low_perf_histogram", { p_report_id: reportId }),
          supabase.rpc("report_exposure_coverage", { p_weekly_report_id: weeklyReportId }),
          supabase.rpc("discovery_exposure_top_panels", { p_date_from: weekStartDate, p_date_to: weekEndDate, p_limit: 20 }),
          supabase.rpc("discovery_exposure_breadth_top", { p_date_from: weekStartDate, p_date_to: weekEndDate, p_limit: 20 }),
        ]);

        const evidence = {
          dataQuality: {
            baselineAvailable: Boolean(prevReportId),
            metadataCoverage: covRes.data || null,
            exposureCoverage: expCovRes.data || null,
            lowPerformanceHistogram: histRes.data || null,
          },
          newIslands: { topByPlays: topNewItems.slice(0, 20), topByPlayers: topNewItems.slice(0, 20) },
          updates: { mostUpdated: mostUpdatedItems.slice(0, 20) },
          exposure: {
            topPanelsByMinutes: topPanelsRes.data || [],
            breadthTop: breadthRes.data || [],
            hasDiscoveryExposure: true,
          },
        };

        computedRankings.evidence = evidence;
      }

      // â”€â”€ Fetch pollution data â”€â”€
      const { data: pollutionRows } = await supabase
        .from("discovery_public_pollution_creators_now")
        .select("*")
        .order("spam_score", { ascending: false })
        .limit(30);
      if (pollutionRows && pollutionRows.length > 0) {
        computedRankings.discoveryPollution = pollutionRows.map((r: any) => ({
          creator_code: r.creator_code,
          spam_score: r.spam_score,
          duplicate_clusters_7d: r.duplicate_clusters_7d,
          duplicate_islands_7d: r.duplicate_islands_7d,
          duplicates_over_min: r.duplicates_over_min,
          sample_titles: r.sample_titles || [],
          as_of: r.as_of,
        }));
      }

      const { data: wrExisting } = await supabase
        .from("weekly_reports")
        .select("id,rebuild_count")
        .eq("id", weeklyReportId)
        .single();

      await supabase.from("weekly_reports").update({
        kpis_json: platformKPIs,
        rankings_json: computedRankings,
        rebuild_count: Number(wrExisting?.rebuild_count || 0) + 1,
        last_rebuilt_at: new Date().toISOString(),
      }).eq("id", weeklyReportId);

      // Audit rebuild run (best-effort)
      try {
        await supabase.from("discover_report_rebuild_runs").insert({
          weekly_report_id: weeklyReportId,
          report_id: reportId,
          user_id: userId,
          ts_start: new Date().toISOString(),
          ts_end: new Date().toISOString(),
          ok: true,
          summary_json: {
            baselineAvailable: Boolean(prevReportId),
            totalIslands: platformKPIs.totalIslands,
            activeIslands: platformKPIs.activeIslands,
            newPublishedCount: platformKPIs.newMapsThisWeekPublished,
            trendingTopics: (trendingData?.trendingTopics || []).length,
          },
        });
      } catch (_e) { /* ignore */ }
    }

    // â”€â”€ Post-processing (required tasks, executed in parallel) â”€â”€
    let aiCompleted = false;
    const postTasks: Promise<void>[] = [];

    if (reinjectExposure && weeklyReportId) {
      postTasks.push((async () => {
        console.log(`[rebuild] Reinjecting exposure for weekly ${weeklyReportId}`);
        const exposureRes = await supabase.functions.invoke("discover-exposure-report", {
          body: { weeklyReportId, embedTimelineLimit: 0, includeCollections: false },
        });
        if (exposureRes.error || (exposureRes.data as any)?.success === false) {
          throw new Error(
            `[rebuild] discover-exposure-report failed: ${exposureRes.error?.message || (exposureRes.data as any)?.error || "unknown error"}`,
          );
        }
      })());
    }

    if (runAi) {
      postTasks.push((async () => {
        console.log(`[rebuild] Running AI for report ${reportId}`);
        const aiRes: any = await supabase.functions.invoke("discover-report-ai", { body: { reportId } });
        if (aiRes.error || (aiRes.data as any)?.success === false) {
          throw new Error(
            `[rebuild] discover-report-ai failed: ${aiRes.error?.message || (aiRes.data as any)?.error || "unknown error"}`,
          );
        }
        aiCompleted = true;
      })());
    }

    await Promise.all(postTasks);

    // Ensure version enrichment is always final and not overwritten by later merges.
    const finalVersionEnrichmentRes = await supabase.rpc("report_version_enrichment", { p_report_id: reportId });
    if (finalVersionEnrichmentRes.error) {
      throw new Error(`[rebuild] report_version_enrichment failed: ${finalVersionEnrichmentRes.error.message}`);
    }
    const finalVersionEnrichment = normalizeRpcJson<any>(finalVersionEnrichmentRes.data);
    if (Object.keys(finalVersionEnrichment).length > 0) {
      const { data: drFresh } = await supabase
        .from("discover_reports")
        .select("computed_rankings")
        .eq("id", reportId!)
        .single();
      const computedMerged = { ...((drFresh?.computed_rankings || {}) as any), versionEnrichment: finalVersionEnrichment };
      await supabase.from("discover_reports").update({ computed_rankings: computedMerged }).eq("id", reportId!);

      if (weeklyReportId) {
        const { data: wrFresh2 } = await supabase
          .from("weekly_reports")
          .select("rankings_json")
          .eq("id", weeklyReportId)
          .single();
        const rankingsMerged = { ...((wrFresh2?.rankings_json || {}) as any), versionEnrichment: finalVersionEnrichment };
        await supabase.from("weekly_reports").update({ rankings_json: rankingsMerged }).eq("id", weeklyReportId);
      }
    }

    // â”€â”€ Mark as completed â”€â”€
    await supabase.from("discover_reports").update({
      status: "completed",
      phase: "done",
      progress_pct: 100,
    }).eq("id", reportId!);

    console.log(`[rebuild] Complete.`);

    return json({
      success: true,
      reportId,
      weeklyReportId,
      baselineAvailable: Boolean(prevReportId),
      totalIslands: platformKPIs.totalIslands,
      activeIslands: platformKPIs.activeIslands,
      newPublishedCount: platformKPIs.newMapsThisWeekPublished,
      trendingTopics: (trendingData?.trendingTopics || []).length,
      ranAi: runAi,
      aiCompleted,
      reinjectedExposure: reinjectExposure,
      buildEvidence,
    });
  } catch (e) {
    console.error("[rebuild] Fatal error:", e);
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

