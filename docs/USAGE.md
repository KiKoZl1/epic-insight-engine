# Usage Guide

This guide covers how to use the platform in the current internal phase.

## Access Levels

- Public: no login required.
- Authenticated user: `/app` area.
- Admin/Editor: `/admin` area.

Roles are resolved from `user_roles`.

## Public Routes

- `/`: home/landing.
- `/discover`: live discovery view.
- `/reports`: published reports list.
- `/reports/:slug`: public report detail.

## Auth

Go to `/auth`.

Supported flows:

1. Email/password sign in.
2. Google OAuth sign in.

## App Area (`/app`)

### Dashboard

- Create and manage projects.
- View project-level uploads and report counts.

### Island Lookup (`/app/island-lookup`)

- Search island by code.
- View metadata, daily metrics, exposure signals, weekly history, category peers, metadata events.

### Project pages

- `/app/projects/:id`
- `/app/projects/:id/reports/:reportId`

Used for project-scoped CSV/report workflows.

## Admin Area (`/admin`)

### Command Center (`/admin`)

- Pipeline health and alerts.
- Cron job state and controls.
- Metadata/exposure/report status.
- Ralph monitoring (runs, actions, evals, incidents, memory stats).

### Reports (`/admin/reports`)

- Review and manage weekly reports.
- Open editor and publish flows.

### Exposure (`/admin/exposure`)

- Exposure target state and operational controls.

### Intel (`/admin/intel`)

- Public intel status and derived metrics.

### Panels (`/admin/panels`)

- Panel-related admin controls.

## Operational Flows

### Weekly report generation

1. Start pipeline from admin.
2. Collector runs catalog/metrics/finalize.
3. Rebuild and AI layers produce final sections.
4. Publish report to public routes.

### Metadata and exposure health

1. Check command center alerts.
2. Verify cron/job execution and stale indicators.
3. Trigger backfill/maintenance modes when needed.

## Troubleshooting

1. Check browser console for frontend errors.
2. Check Supabase Edge Function logs for failing function names.
3. Check command center alerts for pipeline-specific actions.
4. Validate role assignment in `user_roles` if admin screens are blocked.
