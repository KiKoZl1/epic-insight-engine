#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { createClient } from "@supabase/supabase-js";

function asBool(v, fallback = false) {
  if (typeof v === "boolean") return v;
  if (v == null) return fallback;
  const s = String(v).trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(s)) return true;
  if (["0", "false", "no", "n", "off"].includes(s)) return false;
  return fallback;
}

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
    paths: ["docs"],
    includeExt: [".md", ".ts", ".tsx", ".sql", ".json"],
    maxFiles: 250,
    chunkSize: 2200,
    overlap: 200,
    scope: ["project", "ralph"],
    dryRun: false,
    useEmbeddings: true,
    embeddingModel: "text-embedding-3-small",
    importance: 60,
  };

  for (const raw of argv) {
    if (raw.startsWith("--paths=")) args.paths = parseList(raw.slice("--paths=".length), args.paths);
    else if (raw.startsWith("--include-ext=")) args.includeExt = parseList(raw.slice("--include-ext=".length), args.includeExt);
    else if (raw.startsWith("--max-files=")) args.maxFiles = Number(raw.slice("--max-files=".length));
    else if (raw.startsWith("--chunk-size=")) args.chunkSize = Number(raw.slice("--chunk-size=".length));
    else if (raw.startsWith("--overlap=")) args.overlap = Number(raw.slice("--overlap=".length));
    else if (raw.startsWith("--scope=")) args.scope = parseList(raw.slice("--scope=".length), args.scope);
    else if (raw.startsWith("--dry-run=")) args.dryRun = asBool(raw.slice("--dry-run=".length), false);
    else if (raw.startsWith("--use-embeddings=")) args.useEmbeddings = asBool(raw.slice("--use-embeddings=".length), true);
    else if (raw.startsWith("--embedding-model=")) args.embeddingModel = raw.slice("--embedding-model=".length);
    else if (raw.startsWith("--importance=")) args.importance = Number(raw.slice("--importance=".length));
  }

  if (!Number.isFinite(args.maxFiles) || args.maxFiles < 1) args.maxFiles = 250;
  if (!Number.isFinite(args.chunkSize) || args.chunkSize < 400) args.chunkSize = 2200;
  if (!Number.isFinite(args.overlap) || args.overlap < 0) args.overlap = 200;
  if (!Number.isFinite(args.importance) || args.importance < 0 || args.importance > 100) args.importance = 60;

  return args;
}

function normalizePath(p) {
  return String(p || "").replace(/\\/g, "/").replace(/^\.?\//, "");
}

function shouldInclude(file, includeExt) {
  const ext = path.extname(file).toLowerCase();
  return includeExt.map((x) => x.toLowerCase()).includes(ext);
}

function walkFiles(root, includeExt, maxFiles) {
  const out = [];
  const stack = [root];
  while (stack.length && out.length < maxFiles) {
    const cur = stack.pop();
    if (!cur || !fs.existsSync(cur)) continue;
    const st = fs.statSync(cur);
    if (st.isDirectory()) {
      const entries = fs.readdirSync(cur);
      for (const e of entries.reverse()) {
        const next = path.join(cur, e);
        if (e === "node_modules" || e === ".git" || e === "dist" || e.startsWith("scripts/_out")) continue;
        stack.push(next);
      }
    } else if (st.isFile() && shouldInclude(cur, includeExt)) {
      out.push(cur);
    }
  }
  return out;
}

function chunkText(text, chunkSize, overlap) {
  const clean = String(text || "").replace(/\u0000/g, "").trim();
  if (!clean) return [];
  if (clean.length <= chunkSize) return [clean];
  const chunks = [];
  let i = 0;
  while (i < clean.length) {
    const end = Math.min(i + chunkSize, clean.length);
    chunks.push(clean.slice(i, end));
    if (end >= clean.length) break;
    i = Math.max(0, end - overlap);
  }
  return chunks;
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

function sha1(s) {
  return crypto.createHash("sha1").update(s).digest("hex");
}

async function main() {
  loadDotEnvIfPresent();
  const args = parseArgs(process.argv.slice(2));
  const supabaseUrl = mustEnv("SUPABASE_URL", process.env.VITE_SUPABASE_URL || "");
  const serviceRole = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });

  const roots = args.paths.map((p) => path.resolve(p)).filter((p) => fs.existsSync(p));
  if (!roots.length) throw new Error("No valid --paths found.");

  let files = [];
  for (const root of roots) {
    files = files.concat(walkFiles(root, args.includeExt, args.maxFiles));
    if (files.length >= args.maxFiles) break;
  }
  files = Array.from(new Set(files)).slice(0, args.maxFiles);

  let docs = 0;
  let chunksTotal = 0;
  let upserts = 0;
  const errors = [];

  for (const file of files) {
    let text = "";
    try {
      text = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    const normalized = normalizePath(path.relative(process.cwd(), file));
    const chunks = chunkText(text, args.chunkSize, args.overlap);
    if (!chunks.length) continue;
    docs += 1;
    chunksTotal += chunks.length;

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const docKey = `file:${normalized}:chunk:${i + 1}`;
      const title = `${normalized} [${i + 1}/${chunks.length}]`;
      const metadata = {
        path: normalized,
        chunk_index: i + 1,
        chunks_total: chunks.length,
        ingested_at: new Date().toISOString(),
      };
      const hash = sha1(chunk);
      let embeddingText = null;

      try {
        if (!args.dryRun && args.useEmbeddings && process.env.OPENAI_API_KEY) {
          const emb = await getEmbedding(chunk, args.embeddingModel);
          embeddingText = JSON.stringify(emb);
        }

        if (!args.dryRun) {
          const { error } = await supabase.rpc("upsert_ralph_memory_document", {
            p_doc_key: docKey,
            p_doc_type: normalized.endsWith(".md") ? "doc" : "code",
            p_scope: args.scope,
            p_title: title,
            p_content: chunk,
            p_metadata: metadata,
            p_embedding_text: embeddingText,
            p_source_path: normalized,
            p_content_hash: hash,
            p_importance: args.importance,
            p_token_count: Math.ceil(chunk.length / 4),
            p_is_active: true,
          });
          if (error) throw new Error(error.message);
          upserts += 1;
        }
      } catch (err) {
        errors.push({
          file: normalized,
          chunk: i + 1,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  console.log("Ralph memory ingest finished.");
  console.log(`- dry_run: ${args.dryRun}`);
  console.log(`- roots: ${roots.map(normalizePath).join(", ")}`);
  console.log(`- files_scanned: ${files.length}`);
  console.log(`- docs_processed: ${docs}`);
  console.log(`- chunks_total: ${chunksTotal}`);
  console.log(`- upserts: ${upserts}`);
  console.log(`- errors: ${errors.length}`);
  if (errors.length) {
    console.log("- sample_error:", errors[0]);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
