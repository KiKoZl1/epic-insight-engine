# Migration Runbook: Off Lovable Control (Local-First + Own Supabase)

## Goal
Move backend ownership from Lovable-managed project to your own Supabase project, keep development local-first, and remove Lovable AI gateway dependency.

## Owners
- `Founder (you)`: create new Supabase, export/import data, auth/storage dashboard actions.
- `Codex (this repo)`: code changes, scripts, SQL templates, technical validation flow.
- `Lovable`: code copilot only, no secrets/deploy control.

## Responsibility Split (Detailed)
- `Founder`:
  - create and secure new Supabase credentials (DB password, anon key, service role)
  - execute dashboard-only tasks (Auth settings, bucket creation, CSV import UI)
  - export old data and provide reconciliation outputs
  - run smoke checks in real environment and approve phase gates
- `Codex`:
  - keep migration runbook/scripts/SQL maintained in-repo
  - adapt backend functions to provider/env changes
  - provide exact command order and rollback notes
  - support debugging on FK/RLS/cron/auth mapping issues
- `Lovable`:
  - apply UI/code changes requested by you
  - no backend secret custody and no infra ownership

## Phase 0: Pre-Migration Freeze
1. Create branch: `feat/migrate-off-lovable`
2. Freeze deploy changes on Lovable until cutover is complete.
3. Create local artifact folders:
   - `migration_artifacts/exports/`
   - `migration_artifacts/logs/`
4. Run inventory SQL in old project:
   - `migration_artifacts/sql/00_inventory_snapshot.sql`

Exit criteria:
- Old environment inventory exported.
- New Supabase project exists.
- Branch ready.

## Phase 1: Repoint Local Project to New Supabase
1. Copy `.env.example` to `.env` and fill keys.
2. Run:
   - `scripts\\migration-set-target.ps1 -ProjectRef <new_ref> -SupabaseUrl https://<new_ref>.supabase.co -PublishableKey <anon_key>`
3. Link CLI:
   - `supabase login`
   - `supabase link --project-ref <new_ref>`
4. Apply schema:
   - `supabase db push`
5. Deploy functions:
   - `supabase functions deploy ai-analyst`
   - `supabase functions deploy discover-report-ai`
   - deploy remaining `discover-*` functions.

Exit criteria:
- New project linked.
- Migrations applied.
- Functions deployed.

## Phase 2: Full Data Migration (CSV)
1. Export all old tables to CSV.
   - If Lovable UI crashes on big tables, export locally in batches:
     - set old project credentials in `.env` as:
       - `SOURCE_SUPABASE_URL=https://<old-ref>.supabase.co`
       - `SOURCE_SUPABASE_SERVICE_ROLE_KEY=<old-service-role-key>`
     - run:
       - `scripts\\run-export-supabase-tables.bat --batchSize=1000 --outputDir=migration_artifacts/exports`
     - optional (specific tables):
       - `scripts\\run-export-supabase-tables.bat --tables=discover_islands_cache,discover_link_metadata,discover_report_islands --batchSize=1000`
2. Import in dependency order (dimension/base first, facts after).
3. If FK blocks import, use:
   - `migration_artifacts/sql/10_fk_import_window.sql`
4. Re-enable/validate constraints:
   - `migration_artifacts/sql/11_fk_validate.sql`
5. Run reconciliation:
   - `migration_artifacts/sql/30_reconciliation.sql` in old and new.

Exit criteria:
- Counts reconciled (or justified deltas documented).
- No orphan key violations.

## Phase 3: Auth + User ID Remap
1. Recreate users in new Auth.
2. Build mapping CSV: `old_user_id,new_user_id`.
3. Load mapping into temp table and run:
   - `migration_artifacts/sql/20_user_id_remap_template.sql`
4. Validate `user_roles` and ownership fields.

Exit criteria:
- Admin/editor login works.
- Ownership references remapped.

## Phase 4: Storage (Core First)
1. Migrate core buckets used in current app pages.
2. Keep exact bucket names and path structure.
3. Validate media rendering in critical flows.
4. Migrate remaining buckets in a second pass.

Exit criteria:
- Core media flows work.
- Non-core backlog documented.

## Phase 5: AI Provider Cutover
Status in this repo:
- `supabase/functions/discover-report-ai`: migrated to OpenAI (`OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_TRANSLATION_MODEL`)
- `supabase/functions/ai-analyst`: migrated to OpenAI stream (`OPENAI_API_KEY`, `OPENAI_MODEL`)

You must set secrets in new Supabase:
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- optional `OPENAI_TRANSLATION_MODEL`

Exit criteria:
- Report AI and AI analyst work without Lovable gateway.

## Phase 6: Cron + Ops Validation
1. Recreate cron jobs in new project.
2. Validate:
   - exposure orchestrate
   - metadata collector
   - intel refresh
   - report jobs
3. Validate Command Center data freshness.
4. Validate Ralph local run against new service role.

Exit criteria:
- Jobs run without 403.
- Health/alerts show real status.

## Terminal SQL (recommended during migration)
To avoid using the Supabase SQL Editor UI for every change, you can run SQL against the remote database from your local terminal.

1. Install `psql` (PostgreSQL Command Line Tools) on Windows, then reopen your terminal.
2. Set `SUPABASE_DB_URL` in `.env` (see `.env.example`).
3. Run:
   - `scripts\\run-sql.bat -Query "select now();"`
   - `scripts\\run-sql.bat -File migration_artifacts\\sql\\11_fk_validate.sql`

## Acceptance Checklist
1. `/app` loads with new backend.
2. Auth login works for admin/editor.
3. CSV tool and Island Lookup work.
4. Report generation and rebuild work.
5. Discover live/intel pages return data.
6. AI functions return 200 with OpenAI.
7. Reconciliation report stored in `migration_artifacts/logs/`.

## Required Checkpoint Artifacts (what you should send back each phase)
- `Phase 0`: inventory SQL output files, new project ref.
- `Phase 1`: `supabase db push` output, function deploy output.
- `Phase 2`: import status per table + row count comparison CSV.
- `Phase 3`: old->new user map file + orphan check query output.
- `Phase 4`: bucket/object counts before vs after + critical screen screenshots.
- `Phase 5`: report AI function test output + ai-analyst test output.
- `Phase 6`: cron execution evidence + command center screenshots.
