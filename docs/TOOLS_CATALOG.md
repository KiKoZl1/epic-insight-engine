# Tools Catalog

Comprehensive catalog of user-facing tools, execution paths, auth requirements, credit behavior, and observability tables.

## 1. Hub and Tool Inventory

The frontend defines three tool hubs:

- `analyticsTools`
- `thumbTools`
- `widgetKit`

(source: src/tool-hubs/registry.ts:23)

## 2. Tool Matrix

| Hub | Tool ID | Route | Tool Code | Auth Required | Primary Backend Path | Notes |
|---|---|---|---|---|---|---|
| analyticsTools | island-analytics | `/app` | n/a | yes | frontend pages + discover APIs | Workspace analytics surface |
| analyticsTools | island-lookup | `/app/island-lookup` | n/a | yes | discover lookup functions | Lookup-focused workflow |
| analyticsTools | reports | `/reports` | n/a | no | public report APIs | Public reports entry |
| thumbTools | generate | `/app/thumb-tools/generate` | `surprise_gen` | yes | commerce -> `tgis-generate` | Credit debited execution |
| thumbTools | edit-studio | `/app/thumb-tools/edit-studio` | `edit_studio` | yes | commerce -> `tgis-edit-studio` | Asset edit and replacements |
| thumbTools | camera-control | `/app/thumb-tools/camera-control` | `camera_control` | yes | commerce -> `tgis-camera-control` | Camera framing transforms |
| thumbTools | layer-decomposition | `/app/thumb-tools/layer-decomposition` | `layer_decomposition` | yes | commerce -> `tgis-layer-decompose` | Layer extraction |
| widgetKit | psd-umg | `/app/widgetkit/psd-umg` | `psd_to_umg` | yes | commerce local execution branch | Non-TGIS dispatch path |
| widgetKit | umg-verse | `/app/widgetkit/umg-verse` | `umg_to_verse` | yes | commerce local execution branch | Non-TGIS dispatch path |

Evidence:
- Hub + route + tool code map. (source: src/tool-hubs/registry.ts:29)
- Tool code backend map to TGIS handlers. (source: supabase/functions/commerce/index.ts:36)
- Local execution branch for WidgetKit tools. (source: supabase/functions/commerce/index.ts:761)

## 2.1 Dedicated Deep-Dive Docs by Tool

Each tool has a dedicated deep-dive file in `docs/tools/`:

| Tool ID | Dedicated Doc |
|---|---|
| island-analytics | `docs/tools/analytics-island-analytics.md` |
| island-lookup | `docs/tools/analytics-island-lookup.md` |
| reports | `docs/tools/analytics-reports.md` |
| generate | `docs/tools/thumb-generate.md` |
| edit-studio | `docs/tools/thumb-edit-studio.md` |
| camera-control | `docs/tools/thumb-camera-control.md` |
| layer-decomposition | `docs/tools/thumb-layer-decomposition.md` |
| psd-umg | `docs/tools/widgetkit-psd-to-umg.md` |
| umg-verse | `docs/tools/widgetkit-umg-to-verse.md` |

## 3. Commerce Tool Contract

## 3.1 Tool Catalog Endpoint

- `GET /functions/v1/commerce/catalog/tool-costs`

Returns dynamic cost configuration used by frontend cache layer.

Evidence:
- Route mapping in commerce handler. (source: supabase/functions/commerce/index.ts:1563)
- Frontend catalog fetch URL and fallback behavior. (source: src/lib/commerce/toolCosts.ts:91)

### 3.2 Tool Execution Endpoint

- `POST /functions/v1/commerce/tools/execute`

Behavioral stages:

1. Read idempotency and device fingerprint headers.
2. Debit credits via `commerce_debit_tool_credits` RPC.
3. Dispatch to mapped tool function when remote execution is required.
4. Optionally auto-reverse operation on qualifying dispatch failures.

Evidence:
- Execute route mapping. (source: supabase/functions/commerce/index.ts:1587)
- Idempotency header read. (source: supabase/functions/commerce/index.ts:173)
- Debit RPC invocation. (source: supabase/functions/commerce/index.ts:735)
- Auto-reversal branch. (source: supabase/functions/commerce/index.ts:818)

### 3.3 Tool Reverse Endpoint

- `POST /functions/v1/commerce/tools/reverse`

Used for manual or controlled operation reversal.

Evidence:
- Reverse route mapping. (source: supabase/functions/commerce/index.ts:1601)
- Reverse RPC call path. (source: supabase/functions/commerce/index.ts:869)

## 4. Tool Cost Sources

Two cost sources exist:

1. Frontend fallback defaults.
2. Backend dynamic config values.

### 4.1 Frontend Defaults

- `surprise_gen`: 15
- `edit_studio`: 4
- `camera_control`: 3
- `layer_decomposition`: 8
- `psd_to_umg`: 2
- `umg_to_verse`: 2

(source: src/lib/commerce/toolCosts.ts:11)

### 4.2 Backend Config Pull

Commerce backend reads config keys:

- `tool_cost_surprise_gen`
- `tool_cost_edit_studio`
- `tool_cost_camera_control`
- `tool_cost_layer_decomposition`
- `tool_cost_psd_to_umg`
- `tool_cost_umg_to_verse`

(source: supabase/functions/commerce/index.ts:900)

## 5. Tool-Specific Backend Behavior

## 5.1 Generate (`surprise_gen`)

Primary handler: `tgis-generate`.

High-level behavior:

1. Resolve user and role.
2. Enforce commerce gateway signature when enabled.
3. Load runtime config from `tgis_runtime_config`.
4. Assemble references (skin refs, user refs, cluster refs) bounded by config limits.
5. Build prompt pipeline and call generation provider.
6. Write generation log + thumb tool run + asset + cost and skin usage updates.

Evidence:
- Commerce gateway enforcement. (source: supabase/functions/tgis-generate/index.ts:231)
- Runtime config read. (source: supabase/functions/tgis-generate/index.ts:754)
- Ref limit fields from config. (source: supabase/functions/tgis-generate/index.ts:767)
- Blocklist table access. (source: supabase/functions/tgis-generate/index.ts:1948)
- Generation log writes. (source: supabase/functions/tgis-generate/index.ts:2107)
- Thumb tool run writes. (source: supabase/functions/tgis-generate/index.ts:2230)
- Thumb asset writes. (source: supabase/functions/tgis-generate/index.ts:2281)
- Cost and skin usage RPCs. (source: supabase/functions/tgis-generate/index.ts:2356)

## 5.2 Edit Studio (`edit_studio`)

Primary handler: `tgis-edit-studio`.

High-level behavior:

- Validate mode and source asset ownership.
- Resolve replacement skin or custom character context.
- Run FAL model call.
- Update tool run record and persist output asset.

Evidence:
- Handler entry. (source: supabase/functions/tgis-edit-studio/index.ts:73)
- Ownership check through shared helper. (source: supabase/functions/tgis-edit-studio/index.ts:102)
- FAL invocation. (source: supabase/functions/tgis-edit-studio/index.ts:186)
- Tool run update. (source: supabase/functions/tgis-edit-studio/index.ts:224)

## 5.3 Camera Control (`camera_control`)

Primary handler: `tgis-camera-control`.

High-level behavior:

- Validate source asset ownership and camera controls.
- Normalize camera angle semantics for provider.
- Call FAL model and persist generated asset.

Evidence:
- Handler entry. (source: supabase/functions/tgis-camera-control/index.ts:113)
- Ownership check. (source: supabase/functions/tgis-camera-control/index.ts:138)
- FAL call. (source: supabase/functions/tgis-camera-control/index.ts:168)
- Tool run update. (source: supabase/functions/tgis-camera-control/index.ts:210)

## 5.4 Layer Decomposition (`layer_decomposition`)

Primary handler: `tgis-layer-decompose`.

High-level behavior:

- Validate source asset ownership.
- Call provider to extract layers.
- Persist layer outputs and run metadata.

Evidence:
- Handler entry. (source: supabase/functions/tgis-layer-decompose/index.ts:31)
- Ownership load. (source: supabase/functions/tgis-layer-decompose/index.ts:51)
- Provider call path. (source: supabase/functions/tgis-layer-decompose/index.ts:73)

## 5.5 Layer Download

Primary handler: `tgis-layer-download`.

Purpose:

- Download/export layer outputs generated by decomposition workflow.

Evidence: handler file present and wired as edge function. (source: supabase/config.toml:120)

## 5.6 Asset Delete

Primary handler: `tgis-delete-asset`.

Behavior:

- Enforces asset ownership for non-admin users.
- Deletes by `image_url` for all matching assets for user/admin context.

Evidence:
- Ownership enforcement branch. (source: supabase/functions/tgis-delete-asset/index.ts:24)
- Deletion path by image URL. (source: supabase/functions/tgis-delete-asset/index.ts:35)

## 5.7 WidgetKit Local Tools (`psd_to_umg`, `umg_to_verse`)

WidgetKit tools are billed through commerce but executed locally in frontend.

Observed behavior:

1. Frontend calls `executeCommerceTool`.
2. Commerce debits credits and returns success with `dispatch: "client_local"`.
3. Frontend runs parser/generator logic and optionally saves `widgetkit_history`.
4. If local conversion fails after debit, frontend attempts `POST /tools/reverse`.

Evidence:
- Local execution branch and dispatch response. (source: supabase/functions/commerce/index.ts:761, supabase/functions/commerce/index.ts:786)
- Frontend execute and reverse calls. (source: src/components/widgetkit/PsdToUmgTool.tsx:138, src/components/widgetkit/PsdToUmgTool.tsx:175, src/components/widgetkit/UmgToVerseTool.tsx:134, src/components/widgetkit/UmgToVerseTool.tsx:172)
- WidgetKit history persistence client. (source: src/lib/widgetkit/history.ts:6, src/lib/widgetkit/history.ts:18)
- WidgetKit history schema and RLS. (source: supabase/migrations/20260305010000_widgetkit_history.sql:3, supabase/migrations/20260305010000_widgetkit_history.sql:43)

## 6. Shared Thumb Tool Infrastructure

Shared helper module centralizes:

- auth resolution and admin role detection
- commerce gateway verification
- runtime config loading
- FAL invocation helper
- run/asset table writes
- image normalization and storage helpers

Evidence:
- Shared module surface and helpers. (source: supabase/functions/_shared/tgisThumbTools.ts:93)
- Role lookup from `user_roles`. (source: supabase/functions/_shared/tgisThumbTools.ts:140)
- Runtime config loader. (source: supabase/functions/_shared/tgisThumbTools.ts:462)
- FAL model call helper. (source: supabase/functions/_shared/tgisThumbTools.ts:433)

## 7. Admin Tool Observability

Admin pages exposing tool and generation telemetry:

- `/admin/tgis/inference` uses `tgis_generation_log`.
- `/admin/tgis/thumb-tools` uses `tgis_thumb_tool_runs`.
- `/admin/tgis/safety` reads/writes blocklist terms and inspects blocked rows.

Evidence:
- Inference table query. (source: src/pages/admin/tgis/AdminTgisInference.tsx:21)
- Thumb tool runs query. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)
- Safety blocklist operations. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:45)

## 8. Billing Endpoints Related to Tools

Additional billing endpoints affecting tool usage context:

- `POST /billing/subscription/checkout`
- `GET /billing/packs`
- `POST /billing/packs/{pack}/checkout`
- `POST /billing/webhooks/provider`

Evidence: route handlers in commerce backend. (source: supabase/functions/commerce/index.ts:1615)

## 9. Discrepancy Checks

### 9.1 Frontend vs Backend Tool Mapping

No direct mismatch found between frontend tool codes and backend dispatch map for remote tools.

Evidence:
- Frontend tool codes. (source: src/tool-hubs/registry.ts:66)
- Backend dispatch map. (source: supabase/functions/commerce/index.ts:36)

### 9.2 WidgetKit Execution Path

WidgetKit tool codes exist in commerce and receive credits, but execution branch is marked local in backend logic.

Evidence: local branch for `psd_to_umg` and `umg_to_verse`. (source: supabase/functions/commerce/index.ts:761)

## 10. Maintenance Checklist for New Tools

When adding a new tool, update all layers below:

1. Add tool route/page in frontend route tree.
2. Add hub entry in `src/tool-hubs/registry.ts`.
3. Add tool code in `CommerceToolCode` union.
4. Add default cost and config key mapping in frontend.
5. Add backend dispatch mapping in commerce if remote execution.
6. Add backend handler function and register in `supabase/config.toml`.
7. Add observability table/logging path and admin visibility.
8. Update docs and API specs.

Evidence baseline for each step:
- Routes tree. (source: src/App.tsx:116)
- Hub registry. (source: src/tool-hubs/registry.ts:55)
- Tool code union. (source: src/lib/commerce/toolCosts.ts:1)
- Dispatch map. (source: supabase/functions/commerce/index.ts:36)
- Function registration config. (source: supabase/config.toml:75)

## 11. Not Determined From Code

The following cannot be fully proven from repository code alone:

- External product pricing policy outside configured tool cost keys.
- Business support process for manual credit adjustments.

Both are intentionally left undocumented as behavior assertions.

## 12. Related Standards and Coverage Docs

For long-term tool evolution and consistency, use these companion docs:

- `docs/tools/README.md`
- `docs/TOOL_ARCHITECTURE_TEMPLATE.md`
- `docs/BRAND_AND_DESIGN_STANDARDS.md`
- `docs/SYSTEM_COVERAGE_MATRIX.md`

