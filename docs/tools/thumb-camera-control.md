# Tool Deep Dive: Thumb Camera Control (`camera_control`)

## 1. Scope

Camera Control reframes an existing asset by controlling camera azimuth, elevation, and distance using presets or custom values.

- Hub id: `camera-control`. (source: src/tool-hubs/registry.ts:79)
- Route: `/app/thumb-tools/camera-control`. (source: src/tool-hubs/registry.ts:80, src/App.tsx:134)
- Commerce code: `camera_control`. (source: src/tool-hubs/registry.ts:84)

## 2. Frontend Flow

## 2.1 Camera UI Controls

- Page supports presets and custom values. (source: src/pages/thumb-tools/CameraControlPage.tsx:27)
- 3D interaction control is rendered by lazy `CameraGizmo3D`. (source: src/pages/thumb-tools/CameraControlPage.tsx:19, src/pages/thumb-tools/CameraControlPage.tsx:331)

## 2.2 Credit Execution

- Call is sent through `executeCommerceTool` with `toolCode: "camera_control"`. (source: src/pages/thumb-tools/CameraControlPage.tsx:100, src/pages/thumb-tools/CameraControlPage.tsx:101)
- Cost and insufficient-credit states are displayed in UI. (source: src/pages/thumb-tools/CameraControlPage.tsx:283, src/pages/thumb-tools/CameraControlPage.tsx:288)

## 3. Backend Flow: `tgis-camera-control`

## 3.1 Request Validation and Auth

- User/session is resolved in function start. (source: supabase/functions/tgis-camera-control/index.ts:121)
- Commerce gateway check is enforced for `camera_control`. (source: supabase/functions/tgis-camera-control/index.ts:122)
- Source asset ownership is validated before execution. (source: supabase/functions/tgis-camera-control/index.ts:138)

## 3.2 Preset and Value Mapping

- Presets include `heroic`, `confronto`, `epicidade`, `overview`, `cinematic`, `god_view`, `custom`. (source: supabase/functions/tgis-camera-control/index.ts:92)
- Values are clamped to bounded ranges for safety. (source: supabase/functions/tgis-camera-control/index.ts:105, supabase/functions/tgis-camera-control/index.ts:106)
- Non-linear mapping (`gamma`) converts UI angles to provider angles. (source: supabase/functions/tgis-camera-control/index.ts:45, supabase/functions/tgis-camera-control/index.ts:56, supabase/functions/tgis-camera-control/index.ts:65)

## 3.3 Provider Call and Persistence

- Run row is created as `running`. (source: supabase/functions/tgis-camera-control/index.ts:146, supabase/functions/tgis-camera-control/index.ts:151)
- FAL model call uses runtime-configured `camera_model` and `camera_steps`. (source: supabase/functions/tgis-camera-control/index.ts:169, supabase/functions/tgis-camera-control/index.ts:177)
- Output is normalized to stored asset and linked back to run. (source: supabase/functions/tgis-camera-control/index.ts:183, supabase/functions/tgis-camera-control/index.ts:184, supabase/functions/tgis-camera-control/index.ts:210)

## 4. Data Side Effects

- `tgis_thumb_tool_runs` insert/update for execution telemetry. (source: supabase/functions/tgis-camera-control/index.ts:146, supabase/functions/tgis-camera-control/index.ts:250)
- `tgis_thumb_assets` insert for generated reframed image. (source: supabase/functions/tgis-camera-control/index.ts:184)

## 5. Error Model

- Unauthorized requests return 401 path. (source: supabase/functions/tgis-camera-control/index.ts:261)
- Ownership mismatch and forbidden access return 403 path. (source: supabase/functions/tgis-camera-control/index.ts:138)
- Runtime/provider failures update run to `failed` and propagate message. (source: supabase/functions/tgis-camera-control/index.ts:250, supabase/functions/tgis-camera-control/index.ts:268)

## 6. Observability

- Tool-level run telemetry is visible in admin thumb tools panel (`tgis_thumb_tool_runs`). (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)
- Aggregate model/provider distribution and training health are visible in `tgis-health` and admin overview pages. (source: supabase/functions/tgis-health/index.ts:142, src/pages/admin/tgis/AdminTgisOverview.tsx:141)

## 7. Auth/Config Notes

- Route is inside authenticated app shell. (source: src/App.tsx:116, src/App.tsx:134)
- Edge function has `verify_jwt = false`, but runtime user resolution still enforces auth. (source: supabase/config.toml:114, supabase/functions/tgis-camera-control/index.ts:121)

## 8. Maintenance Checklist

1. Keep preset definitions synchronized between frontend and backend when tuning camera UX. (source: src/pages/thumb-tools/CameraControlPage.tsx:27, supabase/functions/tgis-camera-control/index.ts:92)
2. Keep mapping math documented whenever gamma/range constants change. (source: supabase/functions/tgis-camera-control/index.ts:44)
3. Ensure shared normalization remains compatible with camera outputs. (source: supabase/functions/tgis-camera-control/index.ts:183, supabase/functions/_shared/tgisThumbTools.ts:282)
4. Validate admin telemetry still captures `provider_model`, latency, and status transitions. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:36)

## 9. Request Contract (Observed)

Frontend payload fields for execute call:

- `sourceImageUrl`
- `preset`
- `azimuth`
- `elevation`
- `distance`

Evidence:
- Payload assembly in tool page. (source: src/pages/thumb-tools/CameraControlPage.tsx:102, src/pages/thumb-tools/CameraControlPage.tsx:108)

Backend request interpretation:

- Accepts preset values from fixed set plus `custom`.
- Clamps user numeric values to bounded ranges.
- Computes provider-facing angles using mapping helpers.

Evidence:
- Preset parse and fallback. (source: supabase/functions/tgis-camera-control/index.ts:128, supabase/functions/tgis-camera-control/index.ts:132)
- Value clamp logic. (source: supabase/functions/tgis-camera-control/index.ts:101, supabase/functions/tgis-camera-control/index.ts:105)
- Angle mapping helpers. (source: supabase/functions/tgis-camera-control/index.ts:56, supabase/functions/tgis-camera-control/index.ts:65, supabase/functions/tgis-camera-control/index.ts:84)

## 10. User Lifecycle

1. User chooses preset or custom controls.
2. User adjusts sliders or 3D gizmo.
3. Tool executes billed request.
4. Backend reframes source image and persists output.
5. UI displays generated image and handles insufficient-credit state when present.

Evidence:
- Preset and slider controls. (source: src/pages/thumb-tools/CameraControlPage.tsx:250, src/pages/thumb-tools/CameraControlPage.tsx:265)
- 3D gizmo interactions. (source: src/pages/thumb-tools/CameraControlPage.tsx:331, src/pages/thumb-tools/CameraControlPage.tsx:348)
- Execute flow and error payload path. (source: src/pages/thumb-tools/CameraControlPage.tsx:100, src/pages/thumb-tools/CameraControlPage.tsx:114)

## 11. Discrepancy and Confidence Notes

- Function config is `verify_jwt = false`, but runtime requires user context and ownership checks.

Evidence:
- Function flag and runtime auth/ownership enforcement. (source: supabase/config.toml:114, supabase/functions/tgis-camera-control/index.ts:121, supabase/functions/tgis-camera-control/index.ts:138)

`x-doc-confidence: high` for payload mapping and persistence behavior.

## 12. Admin and Support Playbook Hooks

When debugging camera tool incidents, verify in this order:

1. Commerce debit result and operation id.
2. Tool run status in `tgis_thumb_tool_runs`.
3. Provider model and input camera values.
4. Output asset insertion and URL validity.

Evidence:
- Commerce execution path and status sync events. (source: src/lib/commerce/client.ts:176, src/lib/commerce/client.ts:203)
- Run payload values persisted (`azimuth`, `elevation`, `distance`, `preset`). (source: supabase/functions/tgis-camera-control/index.ts:155, supabase/functions/tgis-camera-control/index.ts:159)
- Admin thumb tools telemetry view. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)

## 13. Frontend-Backend Parameter Alignment

Current numeric ranges align between client controls and backend clamps:

- azimuth: `-70..70`
- elevation: `-30..60`
- distance: `0.5..1.5`

Evidence:
- Frontend slider ranges. (source: src/pages/thumb-tools/CameraControlPage.tsx:265, src/pages/thumb-tools/CameraControlPage.tsx:270, src/pages/thumb-tools/CameraControlPage.tsx:275)
- Backend clamp ranges. (source: supabase/functions/tgis-camera-control/index.ts:103, supabase/functions/tgis-camera-control/index.ts:106)

## 14. Not Determined From Code

Not determined from code:

- Whether provider expects additional hidden camera parameters beyond mapped values.
- Any external SLA for turnaround latency by preset.

## 15. Change Impact Checklist

Before merging camera control changes:

1. Confirm slider ranges still match backend clamp ranges.
2. Confirm all presets still exist in frontend and backend.
3. Confirm generated asset persists and appears in UI preview.
4. Confirm insufficient-credit flow still interrupts execution safely.

Evidence:
- Slider ranges and preset list in UI. (source: src/pages/thumb-tools/CameraControlPage.tsx:27, src/pages/thumb-tools/CameraControlPage.tsx:265)
- Preset list and clamp logic in backend. (source: supabase/functions/tgis-camera-control/index.ts:92, supabase/functions/tgis-camera-control/index.ts:103)
- Execute flow and credit UX. (source: src/pages/thumb-tools/CameraControlPage.tsx:100, src/pages/thumb-tools/CameraControlPage.tsx:288)
