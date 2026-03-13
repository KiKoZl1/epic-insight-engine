# Documentation Index

This directory is the technical source of truth for project maintenance.

All docs are evidence-driven and should map claims to concrete code lines.

## 0. Platform Naming Policy

Use only `UEFN Toolkit` as the platform name in all documentation.

## 1. Start Here

1. `../README.md` for project-wide architecture and setup.
2. `DEVELOPER_GUIDE.md` for change workflows.
3. `TOOLS_CATALOG.md` for product tool behavior and credit mapping.

## 2. Core Domain Docs

- `ADMIN_CENTER.md`
  - Admin route map, role gates, UI data sources, and domain ownership.

- `DDPI_ML_SYSTEM.md`
  - End-to-end DPPI architecture: data pipeline, training, release gates, inference, worker runtime.

- `TGIS_LLM_ML_SYSTEM.md`
  - End-to-end TGIS architecture: LLM prompt orchestration, generation, training queue, model lifecycle.

- `RALPH_SYSTEM.md`
  - Ralph autonomous operations runtime, memory model, DB contracts, and incident flows.

- `LLM_ML_RUNBOOK.md`
  - Operator runbook for worker setup, training dispatch, troubleshooting, and recovery.

## 3. Backend and API Specs

- `BACKEND_A.md`
- `BACKEND_B_COMMERCE.md`
- `openapi-backend-a.yaml`
- `openapi-backend-b-commerce.yaml`

## 4. Data and Infra Docs

- `DATABASE.md`
- `INFRASTRUCTURE.md`
- `DEPLOYMENT_RUNBOOK.md`
- `OPERATIONS_RUNBOOK.md`

## 5. ADRs

- `ADR-001-edge-functions-runtime.md`

## 6. Documentation Rules

- Every implementation claim should include `(source: file:line)`.
- If evidence is unavailable in code, mark as `Not determined from code`.
- Do not infer hidden business rules.
- Do not keep stale assumptions when migrations or handlers change.

## 7. Coverage Focus of This Doc Set

This doc set now explicitly covers:

- DDPI internals and releases.
- TGIS LLM/ML and admin workflows.
- Ralph operations and semantic memory.
- Admin Center route and ownership map.
- Tool catalog with backend dispatch and cost semantics.

Evidence that these domains exist in code:

- Admin routes include `/admin/dppi/*` and `/admin/tgis/*`. (source: src/App.tsx:147)
- DPPI edge handlers are present. (source: supabase/config.toml:60)
- TGIS edge handlers are present. (source: supabase/config.toml:75)
- Ralph scripts and DB functions are present. (source: package.json:18, supabase/migrations/20260216123000_ralph_ops_foundation.sql:204)

