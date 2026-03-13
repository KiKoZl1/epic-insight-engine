# UEFN Toolkit Documentation Index

This directory is the technical source of truth for architecture, operations, tooling, and maintenance.

All claims are expected to be code-evidence based.

## 0. Naming Policy

Use only `UEFN Toolkit` as the platform name in all docs.

## 1. Start Here

1. `../README.md` for global architecture, setup, and deployment entrypoints.
2. `DEVELOPER_GUIDE.md` for contributor workflows.
3. `SYSTEM_COVERAGE_MATRIX.md` for system-to-document mapping.

## 2. Platform and Product Surface Docs

- `TOOLS_CATALOG.md`
  - Cross-tool matrix, commerce contract, dispatch model, and discrepancies.

- `tools/README.md`
  - Deep-dive index for every tool.

- `ADMIN_CENTER.md`
  - Admin route map, role gates, UI data sources, and operational dependencies.

## 3. LLM and ML Domain Docs

- `DDPI_ML_SYSTEM.md`
  - DPPI data pipeline, training, inference, releases, and worker runtime.

- `TGIS_LLM_ML_SYSTEM.md`
  - TGIS generation flows, LLM prompt system, model/training lifecycle, and admin operations.

- `RALPH_SYSTEM.md`
  - Ralph runtime, safety model, memory architecture, and operations scripts.

- `LLM_ML_RUNBOOK.md`
  - Operator procedures for runtime health, training tasks, and recovery.

## 4. API and Backend Docs

- `BACKEND_A.md`
- `BACKEND_B_COMMERCE.md`
- `openapi-backend-a.yaml`
- `openapi-backend-b-commerce.yaml`

## 5. Data, Infra, and Ops Docs

- `DATABASE.md`
- `INFRASTRUCTURE.md`
- `DEPLOYMENT_RUNBOOK.md`
- `OPERATIONS_RUNBOOK.md`
- `PAYMENTS_GATEWAY.md`

## 6. Design and Evolution Standards

- `BRAND_AND_DESIGN_STANDARDS.md`
  - Brand naming, token system, typography, nav patterns, and UI consistency rules.

- `TOOL_ARCHITECTURE_TEMPLATE.md`
  - Engineering + documentation template for building new tools.

## 7. Architecture Decisions

- `ADR-001-edge-functions-runtime.md`

## 8. System Coverage Snapshot

The current doc set explicitly covers:

- public discover/report surfaces
- authenticated analytics and tools surfaces
- full tool hub inventory (analytics/thumb/widget)
- admin center (reports/exposure/intel/panels/dppi/tgis/commerce)
- DPPI/TGIS/Ralph runtime and ML workflows
- infra, database, payments, and deployment operations
- brand/design and future tool implementation standards

Evidence:

- Public, app, and admin route trees. (source: src/App.tsx:103, src/App.tsx:116, src/App.tsx:140)
- Tool hubs and routes. (source: src/tool-hubs/registry.ts:23)
- Edge function domains. (source: supabase/config.toml:3)
- ML runtimes and scripts. (source: ml/dppi/runtime.py:1, ml/tgis/runtime/worker_tick.py:1, scripts/ralph_local_runner.py:1)

## 9. Documentation Rules

- Every implementation claim should include `(source: file:line)`.
- If evidence is unavailable, mark as `Not determined from code`.
- Do not infer hidden business intent.
- Update index links when adding/removing docs.
