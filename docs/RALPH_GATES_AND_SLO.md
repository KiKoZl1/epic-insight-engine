# Ralph Gates and SLO

This document defines minimum gates and SLO targets used by Ralph runs.

## Global Mandatory Gates
1. `npm run build` passes
2. `npm run test -- --run` passes
3. No new critical incident opened during run
4. Action trace and eval trace persisted

## Mode-Specific Gates

### dev
- UI route smoke checks pass
- No TypeScript compile errors
- No broken critical navigation (`/app`, `/app/island-lookup`, `/admin`)

### dataops
- Target SQL/RPC returns valid responses
- Pipeline-specific KPI regression does not exceed threshold
- No lock-cascade risk introduced

### report
- `rankings_json.evidence` exists and has required blocks
- Baseline behavior is correct when previous report is missing
- Rebuild operation completes without fatal errors

### qa
- Regression suite for touched domains passes
- Error rate does not increase vs previous baseline run

## Pipeline SLO Targets

### Lookup
- 24h fail rate < 3%
- p95 latency < 2500ms
- internal card coverage > 80%

### Metadata
- Due-now backlog trend descending in active backfill windows
- 429 rate within acceptable baseline

### Exposure
- No target stale beyond 2x configured interval
- maintenance completes without DB instability

### Reports
- Rebuild pass rate > 95%
- Evidence coverage complete for required sections

## Run End Decision
Ralph should set:
- `completed` if mandatory + mode gates pass
- `promotable` if completed + review checklist evidence present
- `failed` or `rolled_back` otherwise

## Review Checklist for Promotion
1. Gate logs attached
2. KPI deltas attached
3. Known risks and rollback noted
4. Migration impact reviewed (if applicable)
5. Smoke routes validated
