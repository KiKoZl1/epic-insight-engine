# PRD: App Value + Data Specialist (Ralph)

## Product Goal
Turn `/app` into a product users would pay for, while training Ralph to become a reliable Discover data specialist.

## Success Criteria
- CSV tool produces actionable insights, not just parsed tables.
- Island Lookup shows complete card context (metadata + exposure + quality hints).
- Ralph runs incrementally on feature backlog and leaves clean artifacts each session.
- Ralph context quality improves over time via operational + semantic memory.

## Scope (Current Cycle)
1. CSV Tool V2 UX and insight quality.
2. Island Lookup V2 clarity, diagnostics and recommendations.
3. Command Center quality signals tied to product usage outcomes.
4. Ralph harness reliability for long-running multi-session work.

## Non-Goals (for this cycle)
- Full autonomous merge/deploy to `main`.
- Replacing the final human review step.
- Rewriting backend architecture.

## Constraints
- Small safe edits per iteration.
- Keep build/test green.
- Respect edit allowlist and max files per iteration.
- No secrets/migration lock/env file edits by runner.

## Required Session Artifacts
- `docs/ralph/progress_log.jsonl` append-only run log.
- `scripts/_out/ralph_local_runner/run_*/ralph_local_runner_summary.json`.
- Feature backlog status tracked in `docs/ralph/feature_backlog.json`.

## Operating Model
1. Pick highest priority feature with `passes=false`.
2. Validate baseline (build/test or selected gates).
3. Implement one incremental improvement.
4. Leave clean state + progress artifact.
5. Continue next session from artifacts and git log.
