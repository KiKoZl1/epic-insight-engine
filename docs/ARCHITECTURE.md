# Architecture Guide

This is the current architecture for Epic Insight Engine in the self-hosted phase (local-first + Supabase-owned backend).

## Runtime Model

1. Frontend: React + Vite app.
2. Backend: Supabase project (Postgres, Auth, Storage, Edge Functions, pg_cron jobs).
3. Automation: Ralph local runner (`scripts/ralph_local_runner.mjs`) + loop harness (`scripts/ralph_loop.ps1`).

## Main Components

### Frontend

- Stack: React 18, TypeScript, React Router, TanStack Query, Tailwind, shadcn/ui.
- Main route groups:
  - Public: `/`, `/discover`, `/reports`, `/reports/:slug`
  - App: `/app`, `/app/island-lookup`, project/report pages
  - Admin: `/admin`, `/admin/reports`, `/admin/exposure`, `/admin/intel`, `/admin/panels`

### Supabase

- Auth: email/password + Google OAuth (configured in Supabase).
- Database: schema versioned in `supabase/migrations`.
- Edge Functions: in `supabase/functions`.
- Cron orchestration: pg_cron jobs calling Edge Functions.

### Edge Function Domains

- Weekly report pipeline:
  - `discover-collector`
  - `discover-report-rebuild`
  - `discover-report-ai`
  - `ai-analyst`
- Discovery/exposure:
  - `discover-exposure-collector`
  - `discover-exposure-report`
  - `discover-exposure-timeline`
- Metadata/links:
  - `discover-links-metadata-collector`
  - `discover-rails-resolver`
- Lookup:
  - `discover-island-lookup`
- Gap tooling:
  - `discover-enqueue-gap`

## Data Domains

1. Reports: weekly report generation, queue, publish payloads.
2. Exposure: panel/surface visibility and rollups.
3. Metadata graph: islands, links, collections, edges.
4. Public intel: premium/emerging/pollution slices.
5. Ralph ops + memory: runs, actions, incidents, context and semantic memory.

## Security Model

- RLS enabled for app tables.
- `user_roles` drives role checks (`admin`, `editor`, `client`).
- Admin operations are enforced by role checks and/or service-role paths.
- Edge Functions requiring privileged operations validate service token or explicit admin/editor access depending on mode.

## Configuration

Core env vars for local development:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `NVIDIA_API_KEY` (preferred for Ralph memory/LLM flows)
- `OPENAI_API_KEY` (optional fallback for selected flows)

See `docs/SETUP.md` for full setup instructions.

## Operational Notes

1. Source of truth for schema and RPCs is `supabase/migrations`.
2. Source of truth for pipelines is Edge Functions + cron jobs in the target Supabase project.
3. `docs/archive/` contains historical references only.
