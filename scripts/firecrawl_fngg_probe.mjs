#!/usr/bin/env node
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";

const TARGETS = [
  { id: "player_count", url: "https://fortnite.gg/player-count" },
  { id: "discover", url: "https://fortnite.gg/discover" },
  { id: "banners", url: "https://fortnite.gg/discover?banners" },
];

function tsStamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function parseArgs(argv) {
  const args = {
    outDir: path.join(process.cwd(), "scripts", "_out", "firecrawl_fngg_probe"),
    timeoutMs: 60000,
  };
  for (const raw of argv) {
    if (raw.startsWith("--out-dir=")) args.outDir = raw.slice("--out-dir=".length);
    else if (raw.startsWith("--timeout-ms=")) args.timeoutMs = Number(raw.split("=")[1] || 60000);
  }
  return args;
}

function toNumber(raw) {
  if (!raw) return null;
  const m = String(raw).match(/([0-9][0-9,]*(?:\.[0-9]+)?)([KMB])?/i);
  if (!m) return null;
  const base = Number(m[1].replace(/,/g, ""));
  if (!Number.isFinite(base)) return null;
  const unit = (m[2] || "").toUpperCase();
  if (unit === "K") return Math.round(base * 1_000);
  if (unit === "M") return Math.round(base * 1_000_000);
  if (unit === "B") return Math.round(base * 1_000_000_000);
  return Math.round(base);
}

function getTextBlob(payload) {
  const md = String(payload?.data?.markdown || "");
  const html = String(payload?.data?.html || "");
  return `${md}\n${html}`;
}

function extractPlayerMetrics(text) {
  const lines = String(text)
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean);

  function findNearLabel(labelRe) {
    for (let i = 0; i < lines.length; i++) {
      if (!labelRe.test(lines[i])) continue;
      for (let j = 1; j <= 3; j++) {
        const n1 = toNumber(lines[i - j]);
        if (n1 != null) return n1;
      }
      for (let j = 1; j <= 3; j++) {
        const n2 = toNumber(lines[i + j]);
        if (n2 != null) return n2;
      }
    }
    return null;
  }

  return {
    players_now: findNearLabel(/players\s+right\s+now/i),
    peak_24h: findNearLabel(/24-?hour\s+peak/i),
    all_time_peak: findNearLabel(/all-?time\s+peak/i),
  };
}

function extractDiscoverSignals(text) {
  const blob = String(text);
  const islandCodeHits = (blob.match(/\b\d{4}-\d{4}-\d{4}\b/g) || []).length;
  const playlistHits = (blob.match(/\bplaylist_[a-z0-9_]+\b/gi) || []).length;
  const ccuHits = (blob.match(/\b[0-9][0-9,]*(?:\.[0-9]+)?\s*[KMB]\b/gi) || []).length;
  const panelHints =
    (blob.match(/\b(homebar|sponsored|epic's picks|top rated|trending|variety|tycoon|horror|pve|roleplay)\b/gi) || [])
      .length;

  return {
    island_code_hits: islandCodeHits,
    playlist_hits: playlistHits,
    ccu_like_hits: ccuHits,
    panel_hint_hits: panelHints,
  };
}

function extractBannerSignals(text) {
  const blob = String(text);
  const ranges = (blob.match(
    /[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}\s+\d{2}:\d{2}\s+UTC\s+[—-]\s+[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}\s+\d{2}:\d{2}\s+UTC/g,
  ) || []).length;
  const imgs = (blob.match(/https:\/\/cdn2\.unrealengine\.com\/[^\s"'<>]+/gi) || []).length;
  return {
    banner_time_range_hits: ranges,
    banner_image_url_hits: imgs,
  };
}

async function firecrawlScrape(apiBase, apiKey, url, timeoutMs) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${apiBase}/scrape`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "x-api-key": apiKey,
        "X-API-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        url,
        formats: ["markdown", "html"],
        onlyMainContent: false,
      }),
      signal: ctrl.signal,
    });

    const raw = await res.text();
    let json = null;
    try {
      json = raw ? JSON.parse(raw) : null;
    } catch {
      json = null;
    }

    return {
      ok: res.ok,
      status: res.status,
      json,
      raw: raw?.slice(0, 3000) || "",
    };
  } finally {
    clearTimeout(t);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = process.env.FIRECRAWL_API_KEY || "";
  const apiBase = process.env.FIRECRAWL_API_BASE || "https://api.firecrawl.dev/v1";
  if (!apiKey) {
    console.error("Missing FIRECRAWL_API_KEY");
    process.exit(1);
  }

  const runDir = path.join(args.outDir, `run_${tsStamp()}`);
  ensureDir(runDir);

  const run = {
    started_at: new Date().toISOString(),
    api_base: apiBase,
    timeout_ms: args.timeoutMs,
    pages: {},
  };

  for (const target of TARGETS) {
    const res = await firecrawlScrape(apiBase, apiKey, target.url, args.timeoutMs);
    const textBlob = getTextBlob(res.json);
    let signals = {};
    if (target.id === "player_count") signals = extractPlayerMetrics(textBlob);
    if (target.id === "discover") signals = extractDiscoverSignals(textBlob);
    if (target.id === "banners") signals = extractBannerSignals(textBlob);

    const pageOut = {
      id: target.id,
      url: target.url,
      ok: res.ok,
      status: res.status,
      success_flag: Boolean(res.json?.success),
      data_url: res.json?.data?.metadata?.sourceURL || res.json?.data?.metadata?.url || null,
      markdown_len: String(res.json?.data?.markdown || "").length,
      html_len: String(res.json?.data?.html || "").length,
      signals,
      error_preview: res.ok ? null : (res.json?.error || res.raw || null),
    };
    run.pages[target.id] = pageOut;

    await fsp.writeFile(path.join(runDir, `${target.id}_response.json`), JSON.stringify(res.json || { raw: res.raw }, null, 2), "utf8");
  }

  run.finished_at = new Date().toISOString();
  run.summary = {
    pages_ok: Object.values(run.pages).filter((p) => p.ok).length,
    player_now: run.pages.player_count?.signals?.players_now ?? null,
    peak_24h: run.pages.player_count?.signals?.peak_24h ?? null,
    discover_score:
      (run.pages.discover?.signals?.island_code_hits || 0) +
      (run.pages.discover?.signals?.playlist_hits || 0) +
      (run.pages.discover?.signals?.ccu_like_hits || 0),
    banners_score:
      (run.pages.banners?.signals?.banner_time_range_hits || 0) +
      (run.pages.banners?.signals?.banner_image_url_hits || 0),
  };

  const summaryPath = path.join(runDir, "firecrawl_fngg_probe_summary.json");
  await fsp.writeFile(summaryPath, JSON.stringify(run, null, 2), "utf8");

  console.log("Firecrawl FN.GG probe done.");
  console.log(`- pages ok: ${run.summary.pages_ok}/3`);
  console.log(`- player now: ${run.summary.player_now ?? "-"}`);
  console.log(`- peak 24h: ${run.summary.peak_24h ?? "-"}`);
  console.log(`- discover score: ${run.summary.discover_score}`);
  console.log(`- banners score: ${run.summary.banners_score}`);
  console.log(`- summary: ${summaryPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
