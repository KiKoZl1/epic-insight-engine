# Tool Deep Dive: Thumb Layer Decomposition (`layer_decomposition`)

## 1. Scope

Layer Decomposition extracts multiple semantic layers from an existing thumbnail asset and supports PNG or ZIP download exports.

- Hub id: `layer-decomposition`. (source: src/tool-hubs/registry.ts:88)
- Route: `/app/thumb-tools/layer-decomposition`. (source: src/tool-hubs/registry.ts:89, src/App.tsx:135)
- Commerce code: `layer_decomposition`. (source: src/tool-hubs/registry.ts:93)

## 2. Frontend Flow

## 2.1 Run Trigger

- Execution uses `executeCommerceTool` with `toolCode: "layer_decomposition"`. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:92, src/pages/thumb-tools/LayerDecompositionPage.tsx:93)
- UI currently sends fixed `numLayers` constant (`FIXED_LAYER_COUNT = 4`). (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:27, src/pages/thumb-tools/LayerDecompositionPage.tsx:97)

## 2.2 Layer Preview and Visibility

- Returned layers are mapped into local `LayerItem[]` and toggled for preview composition. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:117, src/pages/thumb-tools/LayerDecompositionPage.tsx:131)

## 2.3 Download Path

- Download requests call edge function `tgis-layer-download`. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:139)
- UI supports single PNG download and ZIP batch download. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:253, src/pages/thumb-tools/LayerDecompositionPage.tsx:262)

## 2.4 Credit UX

- Tool cost badge and insufficient credit callout are integrated. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:228, src/pages/thumb-tools/LayerDecompositionPage.tsx:230)

## 3. Backend Flow: `tgis-layer-decompose`

## 3.1 Auth and Validation

- Function resolves user and enforces commerce gateway for `layer_decomposition`. (source: supabase/functions/tgis-layer-decompose/index.ts:39, supabase/functions/tgis-layer-decompose/index.ts:40)
- `numLayers` is clamped to runtime config min/max bounds. (source: supabase/functions/tgis-layer-decompose/index.ts:46)
- Source URL is checked through allowlist guard. (source: supabase/functions/tgis-layer-decompose/index.ts:55)

## 3.2 Provider Invocation

- Tool run starts with `running` status in `tgis_thumb_tool_runs`. (source: supabase/functions/tgis-layer-decompose/index.ts:62, supabase/functions/tgis-layer-decompose/index.ts:64)
- FAL layer model executes using runtime `layer_model` and requested count. (source: supabase/functions/tgis-layer-decompose/index.ts:74, supabase/functions/tgis-layer-decompose/index.ts:77)
- Layer URLs are extracted via shared parser helper. (source: supabase/functions/tgis-layer-decompose/index.ts:82)

## 3.3 Semantic Layer Labels

- Each extracted layer is described by vision helper and converted to label using rule mapper (`Background`, `Character`, `Weapon`, etc.). (source: supabase/functions/tgis-layer-decompose/index.ts:20, supabase/functions/tgis-layer-decompose/index.ts:85, supabase/functions/tgis-layer-decompose/index.ts:94)

## 3.4 Run Completion

- Tool run is updated with `success` including layer payload. (source: supabase/functions/tgis-layer-decompose/index.ts:105)
- Failure path updates run as `failed` with error context. (source: supabase/functions/tgis-layer-decompose/index.ts:137)

## 4. Download Backend: `tgis-layer-download`

- Auth is enforced by `resolveUser` before export. (source: supabase/functions/tgis-layer-download/index.ts:34)
- Input file URLs are validated against allowed origins. (source: supabase/functions/tgis-layer-download/index.ts:51)
- Single file path can return raw file bytes when `zip=false` and one file is requested. (source: supabase/functions/tgis-layer-download/index.ts:66)
- Multi-file/default path zips payload with `JSZip` and returns `application/zip`. (source: supabase/functions/tgis-layer-download/index.ts:2, supabase/functions/tgis-layer-download/index.ts:78, supabase/functions/tgis-layer-download/index.ts:89)

## 5. Data Side Effects

- Run telemetry in `tgis_thumb_tool_runs` for decomposition calls. (source: supabase/functions/tgis-layer-decompose/index.ts:62, supabase/functions/tgis-layer-decompose/index.ts:105)
- No new `tgis_thumb_assets` row is created for each output layer in this function; output is returned as layer URL array in run payload.
  - Not determined from code if downstream process persists layer outputs separately.

## 6. Error Model

- `invalid_source_image_url` for missing/untrusted source URL. (source: supabase/functions/tgis-layer-decompose/index.ts:55)
- `layer_model_no_layers` when provider returns empty layer list. (source: supabase/functions/tgis-layer-decompose/index.ts:83)
- Download function emits `unauthorized` -> 401 and generic failures -> 500 JSON payload. (source: supabase/functions/tgis-layer-download/index.ts:96)

## 7. Observability and Admin

- Admin thumb-tools screen includes runs from this tool with mode/status/provider data. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)
- Safety and inference dashboards provide neighboring runtime context for blocked prompts/model behavior. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:21, src/pages/admin/tgis/AdminTgisInference.tsx:21)

## 8. Maintenance Checklist

1. Keep frontend requested layer count policy aligned with backend clamp policy. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:27, supabase/functions/tgis-layer-decompose/index.ts:46)
2. Keep URL allowlist policy synchronized across decomposition and download paths. (source: supabase/functions/tgis-layer-decompose/index.ts:55, supabase/functions/tgis-layer-download/index.ts:51)
3. Re-test ZIP export after any storage/CDN host changes. (source: supabase/functions/tgis-layer-download/index.ts:51, supabase/functions/tgis-layer-download/index.ts:90)
4. Keep run payload schema stable for layer name/url fields consumed by UI. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:117)

## 9. Request Contract (Observed)

Frontend execute payload:

- `sourceImageUrl`
- `numLayers` (currently fixed to `4` in UI)

Evidence:
- Execute payload build. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:93, src/pages/thumb-tools/LayerDecompositionPage.tsx:97)

Backend handling:

- `numLayers` is clamped by runtime config bounds.
- Invalid source URL fails with `invalid_source_image_url`.
- Empty provider output fails with `layer_model_no_layers`.

Evidence:
- Clamp and source checks. (source: supabase/functions/tgis-layer-decompose/index.ts:46, supabase/functions/tgis-layer-decompose/index.ts:56)
- Empty layer error path. (source: supabase/functions/tgis-layer-decompose/index.ts:83)

## 10. Layer Labeling Strategy

Semantic labels are generated by keyword rules over vision description text:

- background/sky/horizon -> `Background_Layer_*`
- character/person/player -> `Character_Layer_*`
- weapon -> `Weapon_Layer_*`
- ui/icon -> `Overlay_Layer_*`
- effect/explosion/smoke/light -> `Fx_Layer_*`
- fallback -> `Scene_Layer_*`

Evidence:
- Label mapper logic. (source: supabase/functions/tgis-layer-decompose/index.ts:20, supabase/functions/tgis-layer-decompose/index.ts:28)

## 11. Download Contract

`tgis-layer-download` accepts layer URL list and supports two output modes:

- single file download (`zip=false` and one file)
- zip bundle output (`zip=true` or multiple files)

Evidence:
- Download request builder in frontend. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:139, src/pages/thumb-tools/LayerDecompositionPage.tsx:148)
- Backend mode switch and response content type. (source: supabase/functions/tgis-layer-download/index.ts:66, supabase/functions/tgis-layer-download/index.ts:78, supabase/functions/tgis-layer-download/index.ts:89)

## 12. Discrepancy and Confidence Notes

- Frontend currently forces fixed layer count (`4`) while backend supports dynamic bounded counts.

Evidence:
- Frontend fixed constant. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:27)
- Backend configurable count. (source: supabase/functions/tgis-layer-decompose/index.ts:46)

`x-doc-confidence: high` for decomposition and export paths.

## 13. Operational Debug Checklist

When decomposition fails:

1. Validate commerce execute result and operation id.
2. Verify source image URL allowlist acceptance.
3. Verify provider returned non-empty layer URLs.
4. Validate layer download endpoint access and response content type.

Evidence:
- Execute path. (source: src/pages/thumb-tools/LayerDecompositionPage.tsx:92)
- URL allowlist checks. (source: supabase/functions/tgis-layer-decompose/index.ts:56, supabase/functions/tgis-layer-download/index.ts:51)
- Empty layer guard. (source: supabase/functions/tgis-layer-decompose/index.ts:83)
- Download response modes. (source: supabase/functions/tgis-layer-download/index.ts:66, supabase/functions/tgis-layer-download/index.ts:89)

## 14. Not Determined From Code

Not determined from code:

- Whether downstream pipeline keeps archival copies for each individual extracted layer.
- External SLA/timeout target for large ZIP layer exports.
