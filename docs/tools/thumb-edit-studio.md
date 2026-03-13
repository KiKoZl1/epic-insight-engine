# Tool Deep Dive: Thumb Edit Studio (`edit_studio`)

## 1. Scope

Edit Studio performs post-generation image edits with three modes: masked edit, character replacement, and custom character replacement.

- Hub id: `edit-studio`. (source: src/tool-hubs/registry.ts:70)
- Route: `/app/thumb-tools/edit-studio`. (source: src/tool-hubs/registry.ts:71, src/App.tsx:133)
- Commerce tool code: `edit_studio`. (source: src/tool-hubs/registry.ts:75)

## 2. Frontend Flow

## 2.1 Mode and Source Selection

- UI mode types are `mask_edit` and `character_replace`, with effective mode including `custom_character`. (source: src/pages/thumb-tools/EditStudioPage.tsx:20, src/pages/thumb-tools/EditStudioPage.tsx:21)
- Source can come from recent assets or local upload path. (source: src/pages/thumb-tools/EditStudioPage.tsx:117, src/pages/thumb-tools/EditStudioPage.tsx:261)

## 2.2 Mask and Character Inputs

- Mask canvas is used for edit and character replace modes. (source: src/pages/thumb-tools/EditStudioPage.tsx:704, src/pages/thumb-tools/EditStudioPage.tsx:717)
- Replacement skin lookup uses `tgis-skins-search`. (source: src/pages/thumb-tools/EditStudioPage.tsx:43)
- Custom character upload stores user reference files. (source: src/pages/thumb-tools/EditStudioPage.tsx:321)

## 2.3 Execution and Credits

- Execution uses `executeCommerceTool` with `toolCode: "edit_studio"`. (source: src/pages/thumb-tools/EditStudioPage.tsx:379, src/pages/thumb-tools/EditStudioPage.tsx:380)
- Tool cost is displayed by `ToolCostBadge`; low balance uses `InsufficientCreditsCallout`. (source: src/pages/thumb-tools/EditStudioPage.tsx:671, src/pages/thumb-tools/EditStudioPage.tsx:673)

## 3. Backend Flow: `tgis-edit-studio`

## 3.1 Auth, Ownership, Commerce

- User is resolved from auth token and role checks. (source: supabase/functions/tgis-edit-studio/index.ts:81)
- Commerce gateway signature check is enforced for `edit_studio`. (source: supabase/functions/tgis-edit-studio/index.ts:82)
- Source asset ownership is validated before editing operations. (source: supabase/functions/tgis-edit-studio/index.ts:270)

## 3.2 Mode Validation and Input Guardrails

- Mode must be one of `mask_edit`, `character_replace`, `custom_character`. (source: supabase/functions/tgis-edit-studio/index.ts:89)
- Mask is required for mask/replace modes. (source: supabase/functions/tgis-edit-studio/index.ts:110)
- Replacement skin id is required for character replacement. (source: supabase/functions/tgis-edit-studio/index.ts:113)
- Custom character URL must pass allowlist validation. (source: supabase/functions/tgis-edit-studio/index.ts:116)

## 3.3 Provider Invocation and Output

- Mask data URLs are uploaded to signed temporary storage before provider invocation. (source: supabase/functions/tgis-edit-studio/index.ts:141)
- FAL call executes with combined source/mask/character image context. (source: supabase/functions/tgis-edit-studio/index.ts:186)
- New output is normalized and saved as a thumb asset. (source: supabase/functions/tgis-edit-studio/index.ts:203)

## 3.4 Persistence

- Run row is created in `tgis_thumb_tool_runs` with `running` state. (source: supabase/functions/tgis-edit-studio/index.ts:120, supabase/functions/tgis-edit-studio/index.ts:125)
- Run row is updated to `success` or `failed` with output/error payload. (source: supabase/functions/tgis-edit-studio/index.ts:224, supabase/functions/tgis-edit-studio/index.ts:256)
- Output asset metadata includes edit mode and source/replacement context fields. (source: supabase/functions/tgis-edit-studio/index.ts:211, supabase/functions/tgis-edit-studio/index.ts:218)

## 4. Shared Dependency Usage

- Runtime config is loaded through shared helper. (source: supabase/functions/tgis-edit-studio/index.ts:86)
- Shared vision helper describes replacement/custom reference for prompt conditioning. (source: supabase/functions/tgis-edit-studio/index.ts:154, supabase/functions/tgis-edit-studio/index.ts:166)
- Shared run/asset wrappers and image normalization are reused. (source: supabase/functions/_shared/tgisThumbTools.ts:503, supabase/functions/_shared/tgisThumbTools.ts:568, supabase/functions/_shared/tgisThumbTools.ts:282)

## 5. Error Model

- Validation returns explicit 400 errors (`invalid_mode`, `mask_required`, `invalid_custom_character_image_url`). (source: supabase/functions/tgis-edit-studio/index.ts:97, supabase/functions/tgis-edit-studio/index.ts:111, supabase/functions/tgis-edit-studio/index.ts:117)
- Ownership failure maps to 403. (source: supabase/functions/tgis-edit-studio/index.ts:270)
- Unauthorized request maps to 401. (source: supabase/functions/tgis-edit-studio/index.ts:268)

## 6. Admin Observability

- Run telemetry is visible in `AdminTgisThumbTools` (`tgis_thumb_tool_runs`). (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)
- Generation-level audit stays available in `AdminTgisInference` (`tgis_generation_log`) for upstream generation contexts. (source: src/pages/admin/tgis/AdminTgisInference.tsx:21)

## 7. Maintenance Checklist

1. Keep mode constants aligned between frontend and backend. (source: src/pages/thumb-tools/EditStudioPage.tsx:20, supabase/functions/tgis-edit-studio/index.ts:25)
2. Keep source asset ownership guard unchanged for non-admin users. (source: supabase/functions/tgis-edit-studio/index.ts:270)
3. Keep mask data URL upload path compatible with shared temp signer. (source: supabase/functions/tgis-edit-studio/index.ts:141, supabase/functions/_shared/tgisThumbTools.ts:617)
4. Revalidate tool run output schema when adding new mode metadata fields. (source: supabase/functions/tgis-edit-studio/index.ts:224)

## 8. Request Contract (Observed)

Frontend payload fields:

- `sourceImageUrl`
- `prompt`
- `mode` (`mask_edit`, `character_replace`, `custom_character`)
- `maskDataUrl` (required for mask-based modes)
- `replacementSkinId` (required for `character_replace`)
- `customCharacterImageUrl` (required for `custom_character`)

Evidence:
- Payload builder in page logic. (source: src/pages/thumb-tools/EditStudioPage.tsx:381, src/pages/thumb-tools/EditStudioPage.tsx:388)

Backend validation:

- `invalid_mode` when mode is missing/invalid.
- `mask_required` for mask-based flows.
- `replacement_skin_required` for replacement flow.
- `invalid_custom_character_image_url` for invalid custom reference.

Evidence:
- Validation branches. (source: supabase/functions/tgis-edit-studio/index.ts:97, supabase/functions/tgis-edit-studio/index.ts:110, supabase/functions/tgis-edit-studio/index.ts:113, supabase/functions/tgis-edit-studio/index.ts:116)

## 9. User Lifecycle and UI States

Typical user flow:

1. Select source image (history or upload).
2. Select mode (mask edit or character replace).
3. Draw/adjust mask where required.
4. Optionally choose replacement skin or custom character image.
5. Execute edit and review generated output.

Evidence:
- Mode and source state. (source: src/pages/thumb-tools/EditStudioPage.tsx:82, src/pages/thumb-tools/EditStudioPage.tsx:117)
- Mask and replacement UI. (source: src/pages/thumb-tools/EditStudioPage.tsx:354, src/pages/thumb-tools/EditStudioPage.tsx:575)
- Execution call and response handling. (source: src/pages/thumb-tools/EditStudioPage.tsx:379, src/pages/thumb-tools/EditStudioPage.tsx:396)

## 10. Side-Effect Summary

- Writes run telemetry to `tgis_thumb_tool_runs`.
- Writes generated output image metadata to `tgis_thumb_assets`.
- Reads skin metadata for `character_replace` mode.

Evidence:
- Run insert/update. (source: supabase/functions/tgis-edit-studio/index.ts:124, supabase/functions/tgis-edit-studio/index.ts:224)
- Asset creation. (source: supabase/functions/tgis-edit-studio/index.ts:203)
- Skin lookup dependency. (source: supabase/functions/tgis-edit-studio/index.ts:147)

## 11. Discrepancy and Confidence Notes

- Function is configured with `verify_jwt = false` while runtime enforces user resolution and role checks.

Evidence:
- Function config and runtime auth resolution. (source: supabase/config.toml:111, supabase/functions/tgis-edit-studio/index.ts:81)

`x-doc-confidence: high` for request validation and persistence paths.

## 12. Frontend-Backend Mode Mapping

Mode mapping between UI and API:

- UI `mask_edit` -> backend `mask_edit`
- UI `character_replace` + skin selected -> backend `character_replace`
- UI `character_replace` + custom image selected -> backend `custom_character`

Evidence:
- Effective mode resolution in UI. (source: src/pages/thumb-tools/EditStudioPage.tsx:358, src/pages/thumb-tools/EditStudioPage.tsx:360)
- Backend accepted mode set. (source: supabase/functions/tgis-edit-studio/index.ts:89)

## 13. Not Determined From Code

Not determined from code:

- Any provider-side moderation policy beyond explicit validation in handler.
- Long-term retention policy for custom character temporary uploads.
