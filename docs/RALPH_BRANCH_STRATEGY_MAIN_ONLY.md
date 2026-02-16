# Branch Strategy (Main-Only Team)

If the team currently has only `main`, do not work directly on it for operational automation.

## Recommended Minimal Strategy
1. Keep `main` as protected release branch.
2. Create short-lived branches per scope:
   - `feat/<scope>`
   - `fix/<scope>`
   - `ops/<scope>`
3. Merge by PR only.
4. Tag deploys (`v1.1.x`) after successful release checks.

## Why this matters for Ralph
Ralph runs can produce iterative changes. Branch isolation is required to:
- avoid accidental release of partial iterations
- allow rollback per run
- preserve auditability

## Practical Workflow
1. Branch from `main`
2. Run Ralph loop on branch
3. Validate gates
4. Open PR with run summary
5. Human review
6. Merge to `main`
7. Deploy via Lovable

## If you absolutely cannot create branches
Use strict safeguards:
1. Disable autopromote
2. Disable direct commits from Ralph
3. Run in recommendation mode only
4. Human applies approved changes manually

Branchless mode should be temporary.
