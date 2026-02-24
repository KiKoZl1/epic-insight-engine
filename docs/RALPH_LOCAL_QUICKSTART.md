# Ralph Local Quickstart

Use this to test Ralph locally before any deploy.

## 0) Long-running artifacts (required)

- PRD: `docs/ralph/PRD_APP_VALUE_AND_DATA_SPECIALIST.md`
- Feature backlog: `docs/ralph/feature_backlog.json`
- Progress log: `docs/ralph/progress_log.jsonl`

## 1) Prerequisites

Set environment variables in PowerShell:

```powershell
$env:SUPABASE_URL="https://<project-ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
```

Runner also loads a local `.env` file automatically when variables are not present in the shell.

Required for LLM mode (NVIDIA/Kimi):

```powershell
$env:NVIDIA_API_KEY="<nvidia-key>"
```

## 2) Ensure DB foundation exists

Apply migration:

`supabase/migrations/20260216123000_ralph_ops_foundation.sql`

Without this migration, runner RPC calls will fail.

## 3) Run dry mode (no LLM cost)

```powershell
scripts\run-ralph-local-runner.bat --mode=qa --dry-run=true --scope=csv,lookup --max-iterations=3
```

Expected:
- creates one row in `ralph_runs`
- creates action/eval rows
- finishes with `completed`
- writes local summary under `scripts/_out/ralph_local_runner/run_*/ralph_local_runner_summary.json`

## 4) Run with LLM (real loop)

NVIDIA (Kimi):

```powershell
scripts\run-ralph-local-runner.bat --mode=qa --dry-run=false --llm-provider=nvidia --llm-model=moonshotai/kimi-k2.5 --scope=csv,lookup --max-iterations=3
```

## 4.1) Enable site/platform edits (safe modes)

Propose edit operations only (no code changes applied):

```powershell
scripts\run-ralph-local-runner.bat --mode=dev --dry-run=false --llm-provider=nvidia --llm-model=moonshotai/kimi-k2.5 --scope=csv,lookup --max-iterations=2 --edit-mode=propose --edit-max-files=2 --edit-allowlist=src/,index.html,docs/
```

Apply edit operations automatically (requires non-main branch by default):

```powershell
git checkout -b feat/ralph-autofix-test
scripts\run-ralph-local-runner.bat --mode=dev --dry-run=false --llm-provider=nvidia --llm-model=moonshotai/kimi-k2.5 --scope=csv,lookup --max-iterations=2 --edit-mode=apply --edit-max-files=2 --edit-allowlist=src/,index.html,docs/ --gate-build=true --gate-test=true
```

Use a dedicated prompt file:

```powershell
scripts\run-ralph-local-runner.bat --mode=dev --dry-run=false --llm-provider=nvidia --llm-model=moonshotai/kimi-k2.5 --scope=csv,lookup --max-iterations=2 --edit-mode=apply --edit-max-files=2 --edit-allowlist=src/,index.html,docs/ --prompt-file=docs/RALPH_SITE_IMPROVEMENT_PROMPT.md --gate-build=true --gate-test=true
```

Notes:
- `--edit-mode=apply` is blocked on `main/master` unless `--require-non-main-branch=false`.
- Proposed operations are saved under `scripts/_out/ralph_local_runner/run_*/patches/*_ops.json`.
- Scope control is enforced by allowlist and max touched files.
- Apply guard is enabled by default:
  - repeated build failure signature (2x) auto-downgrades `apply` to `propose`
  - `apply` only unlocks after stable propose history (`--apply-require-stable-propose-runs`, default `5`)
  - repeated feature loop auto-blocks current feature and rotates to next backlog item
- Safer patch rules are enforced in apply mode:
  - `--apply-min-find-chars` (default `120`)
  - find text must be unique and line-bounded (prevents mid-token corruption).
- Semantic embeddings provider can be controlled with:
  - `--semantic-embedding-provider=auto|nvidia|openai|none`
  - `--semantic-embedding-model=<model-id>`
- Default stack is now NVIDIA-only (`--lock-to-nvidia=true`):
  - chat model: `moonshotai/kimi-k2.5`
  - embedding model: `nvidia/nv-embedqa-e5-v5`
- In `--edit-mode=apply`, if zero operations are applied, run status is `failed`.
- Runner reads `--feature-file` and logs each session to `--progress-file`.
- Feature auto-pass update is enabled by default (`--auto-mark-feature-pass=true`) and only occurs when:
  - `edit-mode=apply`
  - at least one patch was applied
  - `gate-build=true` and `gate-test=true`
  - required gates pass

## 5) Optional quality gates

Enable build/test gates:

```powershell
scripts\run-ralph-local-runner.bat --mode=dev --dry-run=true --gate-build=true --gate-test=true
```

Note: existing project build/test failures will mark run as `failed`.

Lint gate is also available:

```powershell
scripts\run-ralph-local-runner.bat --mode=dev --dry-run=true --gate-lint=true
```

## 6) Useful checks

```sql
select * from public.ralph_runs order by started_at desc limit 5;
select * from public.ralph_actions order by created_at desc limit 20;
select * from public.ralph_eval_results order by created_at desc limit 20;
select public.get_ralph_health(24);
```

Memory context checks:

```sql
select * from public.ralph_memory_snapshots order by created_at desc limit 10;
select * from public.ralph_memory_items order by importance desc, last_seen_at desc limit 20;
select public.get_ralph_context_pack(array['csv','lookup'], 72, 20);
```

## 7) Recommended first validation

1. Run dry mode with 3 iterations.
2. Verify rows + health JSON.
3. Run one LLM mode run with 1-2 iterations.
4. Decide if worth deploying orchestrator to your own scheduler/host.

## 8) Autonomous loop (60 minutes / every 5 minutes)

```powershell
git checkout -b feat/ralph-loop-60m
scripts\run-ralph-loop.bat -Mode dev -Profile propose -DurationMinutes 60 -IntervalSeconds 300 -MaxIterations 1 -EditMaxFiles 1 -EditAllowlist "src/,docs/" -LlmProvider nvidia -LlmModel moonshotai/kimi-k2.5 -Scope "csv,lookup" -PromptFile "docs/RALPH_SITE_IMPROVEMENT_PROMPT.md"
```

The loop writes a consolidated summary in:
- `scripts/_out/ralph_loop/run_*/ralph_loop_summary.json`
