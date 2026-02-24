# Database Guide

This document maps the active database domains.  
The exact schema is versioned in `supabase/migrations` and is the canonical source of truth.

## Core Principles

1. Postgres + RLS for all app data.
2. Roles are controlled via `public.user_roles`.
3. Operational workflows are driven by RPCs and pg_cron.
4. Avoid editing tables manually without recording changes in a new migration.

## Table Domains

### Identity and App

- `profiles`
- `user_roles`
- `projects`
- `uploads`
- `reports`
- `chat_messages`

### Weekly Report Pipeline

- `discover_reports`
- `discover_report_queue`
- `discover_report_islands`
- `discover_report_rebuild_runs`
- `weekly_reports`

### Discovery Cache and Metadata

- `discover_islands`
- `discover_islands_cache`
- `discover_link_metadata`
- `discover_link_metadata_events`
- `discover_link_edges`

### Exposure Pipeline

- `discovery_exposure_targets`
- `discovery_exposure_ticks`
- `discovery_exposure_entries_raw`
- `discovery_exposure_link_state`
- `discovery_exposure_presence_events`
- `discovery_exposure_presence_segments`
- `discovery_exposure_rank_segments`
- `discovery_exposure_rollup_daily`

### Public Intel and Monitoring

- `discovery_panel_tiers`
- `discovery_public_premium_now`
- `discovery_public_emerging_now`
- `discovery_public_pollution_creators_now`
- `system_alerts_current`
- `discover_lookup_pipeline_runs`

### Ralph Operations and Memory

- `ralph_runs`
- `ralph_actions`
- `ralph_eval_results`
- `ralph_incidents`
- `ralph_memory_snapshots`
- `ralph_memory_items`
- `ralph_memory_decisions`
- `ralph_memory_documents`

## Important RPC Families

### Report pipeline

- Queue lifecycle: claim/apply/requeue helpers for `discover_report_queue`
- Finalization helpers: `report_finalize_*`
- Rebuild and coverage helpers

### Exposure pipeline

- Claim/apply tick helpers
- Rollup and maintenance helpers
- Public panel summary helpers

### Metadata and graph

- Metadata enqueue/claim helpers
- Link graph stats and cleanup helpers

### Command center / admin

- `compute_system_alerts`
- Lookup stats and error breakdown RPCs
- Admin cron control RPCs (`admin_*discover_cron*`)

### Ralph

- Run lifecycle: `start_ralph_run`, `finish_ralph_run`
- Telemetry: `record_ralph_action`, `record_ralph_eval`
- Incident flow: `raise_ralph_incident`, `resolve_ralph_incident`
- Health and memory context RPCs

## Migration Rules

1. Never patch schema directly in production dashboards.
2. Add a migration file under `supabase/migrations`.
3. Apply with Supabase CLI.
4. Validate with smoke queries and app/admin checks.

## Data Retention

High-volume tables (for example raw exposure and queue/history tables) must be managed with retention and cleanup functions already present in migrations.  
Before changing retention windows, evaluate storage impact and dashboard dependencies.
