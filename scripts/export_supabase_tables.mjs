#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

function loadDotEnv(filePath = ".env") {
  if (!fs.existsSync(filePath)) return;
  const content = fs.readFileSync(filePath, "utf8");
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const idx = line.indexOf("=");
    if (idx <= 0) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

function parseArgs(argv) {
  const out = {};
  for (const arg of argv) {
    if (!arg.startsWith("--")) continue;
    const eq = arg.indexOf("=");
    if (eq > -1) {
      out[arg.slice(2, eq)] = arg.slice(eq + 1);
    } else {
      out[arg.slice(2)] = "true";
    }
  }
  return out;
}

function csvCell(value) {
  if (value === null || value === undefined) return "";
  let s = "";
  if (typeof value === "object") s = JSON.stringify(value);
  else s = String(value);
  const needsQuote = s.includes(",") || s.includes('"') || s.includes("\n") || s.includes("\r");
  if (!needsQuote) return s;
  return `"${s.replace(/"/g, '""')}"`;
}

function log(msg) {
  process.stdout.write(`${msg}\n`);
}

async function exportTable({
  client,
  schema,
  table,
  batchSize,
  outputDir,
  orderBy,
}) {
  const tableRef = `${schema}.${table}`;
  log(`\n[export] ${tableRef}`);

  const countQuery = client.schema(schema).from(table).select("*", { count: "exact", head: true });
  const { count, error: countError } = await countQuery;
  if (countError) throw new Error(`[${tableRef}] count failed: ${countError.message}`);

  const total = Number(count || 0);
  log(`[info] total rows: ${total}`);
  const outFile = path.join(outputDir, `${schema}.${table}.csv`);
  const ws = fs.createWriteStream(outFile, { encoding: "utf8" });

  if (total === 0) {
    ws.end();
    log(`[ok] wrote empty file: ${outFile}`);
    return { table: tableRef, total: 0, file: outFile };
  }

  let offset = 0;
  let wroteHeader = false;
  let headers = [];

  while (offset < total) {
    const to = Math.min(offset + batchSize - 1, total - 1);
    let query = client.schema(schema).from(table).select("*").range(offset, to);
    if (orderBy) query = query.order(orderBy, { ascending: true });

    const { data, error } = await query;
    if (error) {
      throw new Error(`[${tableRef}] batch ${offset}-${to} failed: ${error.message}`);
    }
    const rows = data || [];
    if (rows.length === 0) break;

    if (!wroteHeader) {
      headers = Object.keys(rows[0]);
      ws.write(`${headers.map(csvCell).join(",")}\n`);
      wroteHeader = true;
    }

    for (const row of rows) {
      ws.write(`${headers.map((h) => csvCell(row[h])).join(",")}\n`);
    }

    offset += rows.length;
    const pct = ((offset / total) * 100).toFixed(1);
    log(`[progress] ${tableRef}: ${offset}/${total} (${pct}%)`);
  }

  await new Promise((resolve) => ws.end(resolve));
  log(`[ok] wrote: ${outFile}`);
  return { table: tableRef, total: offset, file: outFile };
}

async function main() {
  loadDotEnv();
  const args = parseArgs(process.argv.slice(2));

  const sourceUrl = args.url || process.env.SOURCE_SUPABASE_URL || process.env.SUPABASE_URL;
  const sourceServiceKey =
    args.serviceKey || process.env.SOURCE_SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!sourceUrl) throw new Error("Missing source URL. Use --url=... or SOURCE_SUPABASE_URL/SUPABASE_URL");
  if (!sourceServiceKey) {
    throw new Error(
      "Missing source service role key. Use --serviceKey=... or SOURCE_SUPABASE_SERVICE_ROLE_KEY/SUPABASE_SERVICE_ROLE_KEY"
    );
  }

  const schema = args.schema || "public";
  const batchSize = Math.max(1, Number(args.batchSize || "1000"));
  const outputDir = args.outputDir || path.join("migration_artifacts", "exports");
  const orderBy = args.orderBy || "";

  fs.mkdirSync(outputDir, { recursive: true });

  const defaultTables = [
    "discover_islands_cache",
    "discover_link_metadata",
    "discover_link_metadata_events",
    "discover_report_islands",
    "discover_report_queue",
    "discovery_exposure_entries_raw",
    "discovery_exposure_presence_events",
    "discovery_exposure_rank_segments",
  ];

  const tables = (args.tables || defaultTables.join(","))
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
  if (tables.length === 0) throw new Error("No tables provided. Use --tables=table1,table2");

  const client = createClient(sourceUrl, sourceServiceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const startedAt = new Date().toISOString();
  const results = [];
  for (const table of tables) {
    const r = await exportTable({
      client,
      schema,
      table,
      batchSize,
      outputDir,
      orderBy,
    });
    results.push(r);
  }

  const summary = {
    started_at: startedAt,
    ended_at: new Date().toISOString(),
    source_url: sourceUrl,
    schema,
    batch_size: batchSize,
    tables: results,
  };
  const summaryPath = path.join(outputDir, "export_summary.json");
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
  log(`\n[done] summary: ${path.resolve(summaryPath)}`);
}

main().catch((err) => {
  console.error(`[fatal] ${err.message}`);
  process.exit(1);
});

