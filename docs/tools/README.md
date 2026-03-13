# UEFN Toolkit Tool Documentation Index

This directory is the deep-dive documentation layer for all user-facing tools in UEFN Toolkit.

Each tool file documents:

- route and auth chain
- frontend interaction lifecycle
- backend/commerce execution contract
- side effects and persistence
- failure and recovery behavior
- maintenance checklist

## 1. Canonical Tool Inventory

Current tool hubs and tools are derived from frontend registry:

- `analyticsTools`: `island-analytics`, `island-lookup`, `reports`
- `thumbTools`: `generate`, `edit-studio`, `camera-control`, `layer-decomposition`
- `widgetKit`: `psd-umg`, `umg-verse`

Evidence:
- Hub and tool map. (source: src/tool-hubs/registry.ts:23)
- Route bindings. (source: src/App.tsx:118, src/App.tsx:132, src/App.tsx:127)

## 2. Analytics Tool Docs

1. [analytics-island-analytics.md](./analytics-island-analytics.md)
2. [analytics-island-lookup.md](./analytics-island-lookup.md)
3. [analytics-reports.md](./analytics-reports.md)

## 3. Thumb Tool Docs

1. [thumb-generate.md](./thumb-generate.md)
2. [thumb-edit-studio.md](./thumb-edit-studio.md)
3. [thumb-camera-control.md](./thumb-camera-control.md)
4. [thumb-layer-decomposition.md](./thumb-layer-decomposition.md)

## 4. WidgetKit Tool Docs

1. [widgetkit-psd-to-umg.md](./widgetkit-psd-to-umg.md)
2. [widgetkit-umg-to-verse.md](./widgetkit-umg-to-verse.md)

## 5. Shared Contracts Across Tools

- Route guards:
  - Auth routes use `ProtectedRoute`.
  - Admin routes use `AdminRoute`.
  (source: src/App.tsx:116, src/App.tsx:140, src/components/ProtectedRoute.tsx:4, src/components/AdminRoute.tsx:4)

- Commerce execution:
  - Tool billing and execution entrypoint is `POST /tools/execute`.
  - Frontend call abstraction is `executeCommerceTool`.
  (source: supabase/functions/commerce/index.ts:1587, src/lib/commerce/client.ts:176)

- Tool code catalog:
  - Source-of-truth union and default costs are in `src/lib/commerce/toolCosts.ts`.
  (source: src/lib/commerce/toolCosts.ts:1, src/lib/commerce/toolCosts.ts:11)

## 6. Required Structure for New Tool Docs

Every new file under `docs/tools/` must include:

1. Scope and route.
2. User flow and frontend state model.
3. Auth and authorization chain.
4. Backend/commerce endpoint contract.
5. Data side effects (DB/events/external API).
6. Error and recovery map.
7. Discrepancy section (`frontend vs backend` when present).
8. Maintenance checklist.

Reference template:

- `docs/TOOL_ARCHITECTURE_TEMPLATE.md`

## 7. Writing Rules (Strict)

- Every implementation claim must have source marker: `(source: path/file.ts:line)`.
- If not provable in code, mark as `Not determined from code`.
- Do not infer business intent or roadmap.
- Keep this index synchronized with:
  - `docs/TOOLS_CATALOG.md`
  - `docs/SYSTEM_COVERAGE_MATRIX.md`

## 8. Related Core Docs

- `docs/TOOLS_CATALOG.md` for cross-tool matrix and shared contracts.
- `docs/BRAND_AND_DESIGN_STANDARDS.md` for platform UI/brand rules when creating new tool screens.
- `docs/TOOL_ARCHITECTURE_TEMPLATE.md` for implementation and documentation checklist.
