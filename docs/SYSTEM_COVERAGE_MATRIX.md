# UEFN Toolkit System Coverage Matrix

This matrix shows which platform systems exist in code and where each one is documented.

Goal:

- Ensure every major system has at least one dedicated documentation artifact.
- Make documentation gaps visible for future runs.

## 1. Coverage Rules

- A system is marked "covered" only when there is a dedicated doc file.
- Claims in this matrix are based on source files in this repository.
- If a system exists in code but has no dedicated doc, it must be flagged as `gap`.

## 2. Platform-Level System Matrix

| System | Evidence in Code | Primary Docs | Coverage Status |
|---|---|---|---|
| Public Discover and Reports | `src/App.tsx` public routes (`/discover`, `/reports`) | `docs/FRONTEND.md`, `docs/BACKEND_A.md`, `docs/tools/analytics-reports.md` | covered |
| Authenticated Analytics Workspace | `/app`, `/app/island-lookup`, project/report routes in `src/App.tsx` | `docs/FRONTEND.md`, `docs/tools/analytics-island-analytics.md`, `docs/tools/analytics-island-lookup.md` | covered |
| Thumb Tools (Generate/Edit/Camera/Layer) | thumb routes in `src/App.tsx`, tool registry in `src/tool-hubs/registry.ts` | `docs/TOOLS_CATALOG.md`, `docs/TGIS_LLM_ML_SYSTEM.md`, `docs/tools/thumb-*.md` | covered |
| WidgetKit Tools | widget routes in `src/App.tsx`, registry entries in `src/tool-hubs/registry.ts` | `docs/TOOLS_CATALOG.md`, `docs/tools/widgetkit-psd-to-umg.md`, `docs/tools/widgetkit-umg-to-verse.md` | covered |
| Commerce and Billing | commerce edge function and client code | `docs/BACKEND_B_COMMERCE.md`, `docs/PAYMENTS_GATEWAY.md` | covered |
| Admin Center | `/admin/*` route tree and admin pages | `docs/ADMIN_CENTER.md` | covered |
| DPPI ML System | DPPI edge functions, migrations, and Python runtime | `docs/DDPI_ML_SYSTEM.md`, `docs/LLM_ML_RUNBOOK.md` | covered |
| TGIS LLM and ML System | TGIS edge/admin functions and Python runtime | `docs/TGIS_LLM_ML_SYSTEM.md`, `docs/LLM_ML_RUNBOOK.md` | covered |
| Ralph Operations Runtime | Ralph scripts and SQL foundation | `docs/RALPH_SYSTEM.md` | covered |
| Database Schema and RPC Layer | migration set in `supabase/migrations` | `docs/DATABASE.md` | covered |
| Infra and Env Configuration | `supabase/config.toml`, `.env.example`, scripts | `docs/INFRASTRUCTURE.md`, `docs/DEPLOYMENT_RUNBOOK.md`, `docs/OPERATIONS_RUNBOOK.md` | covered |
| Brand and UI Standards | brand config, CSS tokens, navigation components | `docs/BRAND_AND_DESIGN_STANDARDS.md` | covered |
| Tool Build Standards | registry, routing, commerce, nav patterns | `docs/TOOL_ARCHITECTURE_TEMPLATE.md` | covered |

Evidence references:

- Route topology. (source: src/App.tsx:103, src/App.tsx:116, src/App.tsx:140)
- Tool registry. (source: src/tool-hubs/registry.ts:23)
- Edge function declarations. (source: supabase/config.toml:3)
- ML runtime folders and scripts. (source: ml/dppi/runtime.py:1, ml/tgis/runtime/worker_tick.py:1, scripts/ralph_local_runner.py:1)

## 3. Tool-by-Tool Coverage Matrix

| Tool Hub | Tool ID | Route | Dedicated Tool Doc | Status |
|---|---|---|---|---|
| analyticsTools | island-analytics | `/app` | `docs/tools/analytics-island-analytics.md` | covered |
| analyticsTools | island-lookup | `/app/island-lookup` | `docs/tools/analytics-island-lookup.md` | covered |
| analyticsTools | reports | `/reports` | `docs/tools/analytics-reports.md` | covered |
| thumbTools | generate | `/app/thumb-tools/generate` | `docs/tools/thumb-generate.md` | covered |
| thumbTools | edit-studio | `/app/thumb-tools/edit-studio` | `docs/tools/thumb-edit-studio.md` | covered |
| thumbTools | camera-control | `/app/thumb-tools/camera-control` | `docs/tools/thumb-camera-control.md` | covered |
| thumbTools | layer-decomposition | `/app/thumb-tools/layer-decomposition` | `docs/tools/thumb-layer-decomposition.md` | covered |
| widgetKit | psd-umg | `/app/widgetkit/psd-umg` | `docs/tools/widgetkit-psd-to-umg.md` | covered |
| widgetKit | umg-verse | `/app/widgetkit/umg-verse` | `docs/tools/widgetkit-umg-to-verse.md` | covered |

Evidence:
- Tool route and id map. (source: src/tool-hubs/registry.ts:29, src/App.tsx:118, src/App.tsx:132, src/App.tsx:127)

## 4. Admin Domain Coverage Matrix

| Admin Domain | Route Prefix | Backend/Runtime Domain | Dedicated Docs | Status |
|---|---|---|---|---|
| Reports | `/admin/reports` | discover reports and editorial flows | `docs/ADMIN_CENTER.md`, `docs/BACKEND_A.md` | covered |
| Exposure | `/admin/exposure` | discover exposure timeline and health | `docs/ADMIN_CENTER.md`, `docs/BACKEND_A.md` | covered |
| Intel | `/admin/intel` | discover intel refresh and panel data | `docs/ADMIN_CENTER.md`, `docs/BACKEND_A.md` | covered |
| Panels | `/admin/panels` | panel manager data contracts | `docs/ADMIN_CENTER.md` | covered |
| DPPI | `/admin/dppi/*` | DPPI APIs + ML pipelines | `docs/ADMIN_CENTER.md`, `docs/DDPI_ML_SYSTEM.md` | covered |
| TGIS | `/admin/tgis/*` | TGIS APIs + LLM/ML runtime | `docs/ADMIN_CENTER.md`, `docs/TGIS_LLM_ML_SYSTEM.md` | covered |
| Commerce | `/admin/commerce` | billing/admin credit operations | `docs/ADMIN_CENTER.md`, `docs/BACKEND_B_COMMERCE.md`, `docs/PAYMENTS_GATEWAY.md` | covered |

Evidence:
- Admin route map. (source: src/App.tsx:140, src/App.tsx:164)

## 5. LLM and ML Coverage Matrix

| Domain | Training | Inference | Release/Promotion | Dedicated Docs | Status |
|---|---|---|---|---|---|
| DPPI | `dppi-train-dispatch`, `ml/dppi/train_*.py` | `discover-dppi-*`, `ml/dppi/batch_inference.py` | `dppi-release-set`, `ml/dppi/publish_model.py` | `docs/DDPI_ML_SYSTEM.md`, `docs/LLM_ML_RUNBOOK.md` | covered |
| TGIS | `tgis-admin-start-training`, `ml/tgis/training/*` | `tgis-generate`, thumb tool functions | `tgis-admin-promote-model`, rollback/delete model functions | `docs/TGIS_LLM_ML_SYSTEM.md`, `docs/LLM_ML_RUNBOOK.md` | covered |
| Ralph | script-driven orchestration only in repo evidence | Not determined from code as model hosting runtime | Not determined from code | `docs/RALPH_SYSTEM.md` | covered |

Evidence:
- DPPI function declarations. (source: supabase/config.toml:60, supabase/config.toml:69)
- TGIS function declarations. (source: supabase/config.toml:75, supabase/config.toml:87, supabase/config.toml:96)
- ML runtime file presence. (source: ml/dppi/train_entry_model.py:1, ml/tgis/training/queue.py:1)
- Ralph scripts. (source: scripts/ralph_local_runner.py:1, scripts/ralph_query_memory.py:1)

## 6. Current Gap Assessment

No uncovered high-level system was found based on current route map, edge function registry, and ML/runtime folders.

`x-doc-confidence: high` for system presence and documentation mapping.

`x-doc-confidence: medium` for future roadmap completeness because roadmap artifacts are not fully represented in code files.

## 7. Maintenance Instructions

On each documentation daily run:

1. Rebuild this matrix from `src/App.tsx`, `src/tool-hubs/registry.ts`, `supabase/config.toml`, and `ml/*`.
2. Mark any new route/function/model domain as `gap` until dedicated docs are added.
3. Keep links synchronized with `docs/README.md` and `docs/tools/README.md`.
