#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

function parseList(v, fallback = []) {
  if (!v) return fallback;
  const out = String(v)
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
  return out.length ? out : fallback;
}

function loadDotEnvIfPresent(filePath = path.join(process.cwd(), ".env")) {
  if (!fs.existsSync(filePath)) return;
  const text = fs.readFileSync(filePath, "utf8");
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    const key = m[1];
    let val = m[2] ?? "";
    if ((val.startsWith("\"") && val.endsWith("\"")) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = val;
  }
}

function mustEnv(name, fallback = "") {
  const v = process.env[name] || fallback;
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function parseArgs(argv) {
  const args = {
    query: "",
    scope: ["project", "ralph"],
    matchCount: 8,
    minImportance: 0,
    useEmbeddings: true,
    embeddingModel: "text-embedding-3-small",
  };
  for (const raw of argv) {
    if (raw.startsWith("--query=")) args.query = raw.slice("--query=".length);
    else if (raw.startsWith("--scope=")) args.scope = parseList(raw.slice("--scope=".length), args.scope);
    else if (raw.startsWith("--match-count=")) args.matchCount = Number(raw.slice("--match-count=".length));
    else if (raw.startsWith("--min-importance=")) args.minImportance = Number(raw.slice("--min-importance=".length));
    else if (raw.startsWith("--use-embeddings=")) args.useEmbeddings = ["1", "true", "yes"].includes(raw.slice("--use-embeddings=".length).toLowerCase());
    else if (raw.startsWith("--embedding-model=")) args.embeddingModel = raw.slice("--embedding-model=".length);
  }
  if (!args.query.trim()) throw new Error("Missing --query");
  if (!Number.isFinite(args.matchCount) || args.matchCount < 1) args.matchCount = 8;
  if (!Number.isFinite(args.minImportance) || args.minImportance < 0) args.minImportance = 0;
  return args;
}

async function getEmbedding(input, model) {
  const apiKey = mustEnv("OPENAI_API_KEY");
  const res = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: model || "text-embedding-3-small",
      input,
    }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`OpenAI embeddings error ${res.status}: ${raw.slice(0, 300)}`);
  const json = JSON.parse(raw);
  const emb = json?.data?.[0]?.embedding;
  if (!Array.isArray(emb) || emb.length === 0) throw new Error("Invalid embedding response");
  return emb;
}

async function main() {
  loadDotEnvIfPresent();
  const args = parseArgs(process.argv.slice(2));

  const supabaseUrl = mustEnv("SUPABASE_URL", process.env.VITE_SUPABASE_URL || "");
  const serviceRole = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });

  let embeddingText = null;
  if (args.useEmbeddings && process.env.OPENAI_API_KEY) {
    const emb = await getEmbedding(args.query, args.embeddingModel);
    embeddingText = JSON.stringify(emb);
  }

  const { data, error } = await supabase.rpc("search_ralph_memory_documents", {
    p_query_text: args.query,
    p_query_embedding_text: embeddingText,
    p_scope: args.scope,
    p_match_count: args.matchCount,
    p_min_importance: args.minImportance,
  });
  if (error) throw new Error(error.message);

  const rows = Array.isArray(data) ? data : [];
  console.log("Ralph memory query results:");
  console.log(`- query: ${args.query}`);
  console.log(`- scope: ${args.scope.join(",")}`);
  console.log(`- matches: ${rows.length}`);
  for (const row of rows.slice(0, 10)) {
    console.log(`  - [${row.score}] ${row.doc_key} :: ${row.title}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
