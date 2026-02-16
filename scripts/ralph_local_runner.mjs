#!/usr/bin/env node
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";

const VALID_MODES = new Set(["dev", "dataops", "report", "qa", "custom"]);

function tsStamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function asBool(v, fallback = false) {
  if (typeof v === "boolean") return v;
  if (v == null) return fallback;
  const s = String(v).trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(s)) return true;
  if (["0", "false", "no", "n", "off"].includes(s)) return false;
  return fallback;
}

function parseArgs(argv) {
  const args = {
    mode: "qa",
    dryRun: true,
    llmProvider: "none",
    llmModel: "",
    scope: ["csv", "lookup"],
    maxIterations: 3,
    timeoutMinutes: 20,
    budgetUsd: 0,
    tokenBudget: 0,
    gateBuild: false,
    gateTest: false,
    outDir: path.join(process.cwd(), "scripts", "_out", "ralph_local_runner"),
    prompt: "Improve reliability and product quality for CSV and Island Lookup.",
  };

  for (const raw of argv) {
    if (raw.startsWith("--mode=")) args.mode = raw.slice("--mode=".length);
    else if (raw.startsWith("--dry-run=")) args.dryRun = asBool(raw.slice("--dry-run=".length), true);
    else if (raw.startsWith("--llm-provider=")) args.llmProvider = raw.slice("--llm-provider=".length);
    else if (raw.startsWith("--llm-model=")) args.llmModel = raw.slice("--llm-model=".length);
    else if (raw.startsWith("--scope=")) {
      const s = raw
        .slice("--scope=".length)
        .split(",")
        .map((x) => x.trim())
        .filter(Boolean);
      if (s.length > 0) args.scope = s;
    } else if (raw.startsWith("--max-iterations=")) args.maxIterations = Number(raw.slice("--max-iterations=".length));
    else if (raw.startsWith("--timeout-minutes=")) args.timeoutMinutes = Number(raw.slice("--timeout-minutes=".length));
    else if (raw.startsWith("--budget-usd=")) args.budgetUsd = Number(raw.slice("--budget-usd=".length));
    else if (raw.startsWith("--token-budget=")) args.tokenBudget = Number(raw.slice("--token-budget=".length));
    else if (raw.startsWith("--gate-build=")) args.gateBuild = asBool(raw.slice("--gate-build=".length), false);
    else if (raw.startsWith("--gate-test=")) args.gateTest = asBool(raw.slice("--gate-test=".length), false);
    else if (raw.startsWith("--out-dir=")) args.outDir = raw.slice("--out-dir=".length);
    else if (raw.startsWith("--prompt=")) args.prompt = raw.slice("--prompt=".length);
  }

  if (!VALID_MODES.has(args.mode)) args.mode = "custom";
  if (!Number.isFinite(args.maxIterations) || args.maxIterations < 1) args.maxIterations = 3;
  if (!Number.isFinite(args.timeoutMinutes) || args.timeoutMinutes < 1) args.timeoutMinutes = 20;
  if (!Number.isFinite(args.budgetUsd) || args.budgetUsd < 0) args.budgetUsd = 0;
  if (!Number.isFinite(args.tokenBudget) || args.tokenBudget < 0) args.tokenBudget = 0;
  return args;
}

function getEnv(name, fallback = "") {
  return process.env[name] || fallback;
}

function mustEnv(name, fallback = "") {
  const v = getEnv(name, fallback);
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function runShell(command, cwd = process.cwd()) {
  const isWin = process.platform === "win32";
  const exe = isWin ? "powershell.exe" : "bash";
  const cmdArgs = isWin
    ? ["-NoProfile", "-NonInteractive", "-Command", command]
    : ["-lc", command];
  const started = Date.now();
  const res = spawnSync(exe, cmdArgs, {
    cwd,
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 10,
  });
  return {
    command,
    code: typeof res.status === "number" ? res.status : 1,
    latencyMs: Date.now() - started,
    stdout: String(res.stdout || "").slice(-4000),
    stderr: String(res.stderr || "").slice(-4000),
  };
}

function buildPrompt(args, iteration) {
  return [
    "You are Ralph runner in Epic Insight Engine.",
    `Mode: ${args.mode}`,
    `Iteration: ${iteration}/${args.maxIterations}`,
    `Scope: ${args.scope.join(", ")}`,
    `Goal: ${args.prompt}`,
    "Return concise JSON with keys: plan, risks, next_action.",
  ].join("\n");
}

async function callOpenAI(prompt, model) {
  const apiKey = mustEnv("OPENAI_API_KEY");
  const m = model || "gpt-4.1-mini";
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: m,
      input: prompt,
      temperature: 0.2,
    }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`OpenAI error ${res.status}: ${raw.slice(0, 300)}`);
  const json = JSON.parse(raw);
  const text = Array.isArray(json.output)
    ? json.output
        .flatMap((o) => o.content || [])
        .map((c) => c.text || "")
        .join("\n")
    : "";
  return { provider: "openai", model: m, text: text.trim(), raw: json };
}

async function callAnthropic(prompt, model) {
  const apiKey = mustEnv("ANTHROPIC_API_KEY");
  const m = model || "claude-3-5-sonnet-latest";
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: m,
      max_tokens: 600,
      temperature: 0.2,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`Anthropic error ${res.status}: ${raw.slice(0, 300)}`);
  const json = JSON.parse(raw);
  const text = Array.isArray(json.content) ? json.content.map((c) => c.text || "").join("\n") : "";
  return { provider: "anthropic", model: m, text: text.trim(), raw: json };
}

async function callLlm(args, iteration) {
  const prompt = buildPrompt(args, iteration);
  const provider = String(args.llmProvider || "none").toLowerCase();
  if (provider === "openai") return callOpenAI(prompt, args.llmModel);
  if (provider === "anthropic") return callAnthropic(prompt, args.llmModel);
  return { provider: "none", model: "dry-run", text: `Dry run iteration ${iteration}: no LLM call.`, raw: { dry_run: true } };
}

async function rpc(supabase, fn, params) {
  const { data, error } = await supabase.rpc(fn, params);
  if (error) throw new Error(`${fn} failed: ${error.message}`);
  return data;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const supabaseUrl = mustEnv("SUPABASE_URL", getEnv("VITE_SUPABASE_URL", ""));
  const serviceRole = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });

  const runDir = path.join(args.outDir, `run_${tsStamp()}`);
  ensureDir(runDir);
  const localLog = {
    started_at: new Date().toISOString(),
    args,
    run_id: null,
    actions: [],
    evals: [],
    incidents: [],
    llm_outputs: [],
    gate_results: [],
  };

  const runId = await rpc(supabase, "start_ralph_run", {
    p_mode: args.mode,
    p_created_by: null,
    p_target_scope: args.scope,
    p_max_iterations: args.maxIterations,
    p_timeout_minutes: args.timeoutMinutes,
    p_budget_usd: args.budgetUsd,
    p_token_budget: args.tokenBudget,
    p_summary: {
      runner: "scripts/ralph_local_runner.mjs",
      dry_run: args.dryRun,
      llm_provider: args.llmProvider,
      llm_model: args.llmModel || null,
    },
  });
  localLog.run_id = runId;

  let failed = false;
  let errorMessage = null;
  const startedAt = Date.now();

  try {
    for (let i = 1; i <= args.maxIterations; i++) {
      if (Date.now() - startedAt > args.timeoutMinutes * 60_000) {
        throw new Error(`Run timeout exceeded (${args.timeoutMinutes} min).`);
      }

      const llm = args.dryRun
        ? { provider: "none", model: "dry-run", text: `Dry plan ${i}`, raw: { dry_run: true, iteration: i } }
        : await callLlm(args, i);
      localLog.llm_outputs.push({ iteration: i, provider: llm.provider, model: llm.model, text_preview: llm.text.slice(0, 500) });

      const actionId = await rpc(supabase, "record_ralph_action", {
        p_run_id: runId,
        p_step_index: i,
        p_phase: "execute",
        p_tool_name: args.dryRun ? "dry_runner" : `${llm.provider}:${llm.model}`,
        p_target: args.scope.join(","),
        p_status: "ok",
        p_latency_ms: 30,
        p_details: {
          iteration: i,
          text_preview: llm.text.slice(0, 500),
          dry_run: args.dryRun,
        },
      });
      localLog.actions.push({ iteration: i, action_id: actionId });

      const evalPass = llm.text.length > 0;
      const evalId = await rpc(supabase, "record_ralph_eval", {
        p_run_id: runId,
        p_suite: "iteration",
        p_metric: "llm_output_non_empty",
        p_value: llm.text.length,
        p_threshold: 1,
        p_pass: evalPass,
        p_details: { iteration: i },
      });
      localLog.evals.push({ iteration: i, eval_id: evalId, pass: evalPass });

      if (!evalPass) {
        failed = true;
        errorMessage = `Iteration ${i} produced empty output`;
        await rpc(supabase, "raise_ralph_incident", {
          p_run_id: runId,
          p_severity: "error",
          p_incident_type: "empty_llm_output",
          p_message: errorMessage,
          p_metadata: { iteration: i },
        });
        break;
      }
    }

    if (!failed && args.gateBuild) {
      const buildRes = runShell("npm run build");
      localLog.gate_results.push({ gate: "build", ...buildRes });
      await rpc(supabase, "record_ralph_action", {
        p_run_id: runId,
        p_step_index: args.maxIterations + 1,
        p_phase: "gate",
        p_tool_name: "npm",
        p_target: "build",
        p_status: buildRes.code === 0 ? "ok" : "error",
        p_latency_ms: buildRes.latencyMs,
        p_details: { stdout: buildRes.stdout, stderr: buildRes.stderr },
      });
      await rpc(supabase, "record_ralph_eval", {
        p_run_id: runId,
        p_suite: "gates",
        p_metric: "build_exit_code",
        p_value: buildRes.code,
        p_threshold: 0,
        p_pass: buildRes.code === 0,
        p_details: { command: buildRes.command },
      });
      if (buildRes.code !== 0) {
        failed = true;
        errorMessage = "Build gate failed";
      }
    }

    if (!failed && args.gateTest) {
      const testRes = runShell("npm run test -- --run");
      localLog.gate_results.push({ gate: "test", ...testRes });
      await rpc(supabase, "record_ralph_action", {
        p_run_id: runId,
        p_step_index: args.maxIterations + 2,
        p_phase: "gate",
        p_tool_name: "npm",
        p_target: "test",
        p_status: testRes.code === 0 ? "ok" : "error",
        p_latency_ms: testRes.latencyMs,
        p_details: { stdout: testRes.stdout, stderr: testRes.stderr },
      });
      await rpc(supabase, "record_ralph_eval", {
        p_run_id: runId,
        p_suite: "gates",
        p_metric: "test_exit_code",
        p_value: testRes.code,
        p_threshold: 0,
        p_pass: testRes.code === 0,
        p_details: { command: testRes.command },
      });
      if (testRes.code !== 0) {
        failed = true;
        errorMessage = "Test gate failed";
      }
    }
  } catch (err) {
    failed = true;
    errorMessage = err instanceof Error ? err.message : String(err);
    localLog.incidents.push({ type: "runner_exception", message: errorMessage });
    await rpc(supabase, "raise_ralph_incident", {
      p_run_id: runId,
      p_severity: "critical",
      p_incident_type: "runner_exception",
      p_message: errorMessage,
      p_metadata: {},
    });
  }

  const finalStatus = failed ? "failed" : args.dryRun ? "completed" : "promotable";
  const finishData = await rpc(supabase, "finish_ralph_run", {
    p_run_id: runId,
    p_status: finalStatus,
    p_summary: {
      local_runner: true,
      dry_run: args.dryRun,
      llm_provider: args.llmProvider,
      scope: args.scope,
      gates: {
        build: args.gateBuild,
        test: args.gateTest,
      },
    },
    p_error_message: errorMessage,
    p_spent_tokens: 0,
    p_spent_usd: 0,
  });

  const health = await rpc(supabase, "get_ralph_health", { p_hours: 24 });

  localLog.finished_at = new Date().toISOString();
  localLog.final_status = finalStatus;
  localLog.finish_data = finishData;
  localLog.health = health;
  localLog.error = errorMessage;

  const outPath = path.join(runDir, "ralph_local_runner_summary.json");
  await fsp.writeFile(outPath, JSON.stringify(localLog, null, 2), "utf8");

  console.log("Ralph local runner finished.");
  console.log(`- run_id: ${runId}`);
  console.log(`- status: ${finalStatus}`);
  console.log(`- dry_run: ${args.dryRun}`);
  console.log(`- mode: ${args.mode}`);
  console.log(`- gates: build=${args.gateBuild} test=${args.gateTest}`);
  console.log(`- summary: ${outPath}`);

  if (failed) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
