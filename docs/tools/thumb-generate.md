# Tool Deep Dive: Thumb Generate (`surprise_gen`)

## 1. Scope

Thumb Generate is the primary AI thumbnail creation tool in UEFN Toolkit.

- Hub tool id: `generate`. (source: src/tool-hubs/registry.ts:61)
- Tool route: `/app/thumb-tools/generate`. (source: src/tool-hubs/registry.ts:62, src/App.tsx:132)
- Commerce tool code: `surprise_gen`. (source: src/tool-hubs/registry.ts:66)

## 2. Frontend Flow

## 2.1 Input and Context Collection

- Main page component is `ThumbGenerator`. (source: src/pages/ThumbGenerator.tsx:29)
- Prompt, skin query, reference upload, and generation phase UI are handled client-side. (source: src/pages/ThumbGenerator.tsx:123, src/pages/ThumbGenerator.tsx:104, src/pages/ThumbGenerator.tsx:218)
- Skin search uses edge function `tgis-skins-search`. (source: src/pages/ThumbGenerator.tsx:105)

## 2.2 Prompt Rewrite

- Optional rewrite button invokes `tgis-rewrite-prompt`. (source: src/pages/ThumbGenerator.tsx:361)
- Rewritten prompt is applied with rollback-to-original toggling. (source: src/pages/ThumbGenerator.tsx:339, src/pages/ThumbGenerator.tsx:396)

## 2.3 Credit Execution

- Tool execution calls `executeCommerceTool` with `toolCode: "surprise_gen"`. (source: src/pages/ThumbGenerator.tsx:293, src/pages/ThumbGenerator.tsx:294)
- Client uses dynamic tool cost via `useToolCosts` + `ToolCostBadge`. (source: src/pages/ThumbGenerator.tsx:116, src/pages/ThumbGenerator.tsx:578)
- Insufficient credit response renders `InsufficientCreditsCallout`. (source: src/pages/ThumbGenerator.tsx:314, src/pages/ThumbGenerator.tsx:585)

## 3. Commerce Gateway Flow

- Frontend sends `/tools/execute` through commerce client. (source: src/lib/commerce/client.ts:191)
- Commerce function debits credits via `commerce_debit_tool_credits`. (source: supabase/functions/commerce/index.ts:735)
- Dispatch map routes `surprise_gen` to `tgis-generate`. (source: supabase/functions/commerce/index.ts:36)

## 4. Backend Flow: `tgis-generate`

## 4.1 Auth and Commerce Guard

- Function resolves user and role from auth token + `user_roles`. (source: supabase/functions/tgis-generate/index.ts:734, supabase/functions/tgis-generate/index.ts:744)
- Commerce gateway signature validation is enforced when configured. (source: supabase/functions/tgis-generate/index.ts:231)

## 4.2 Runtime Config and Safety

- Runtime config is loaded from `tgis_runtime_config`. (source: supabase/functions/tgis-generate/index.ts:752, supabase/functions/tgis-generate/index.ts:754)
- Generation allowance check uses RPC `tgis_can_generate`. (source: supabase/functions/tgis-generate/index.ts:2002)
- Prompt blocklist/safety checks run before generation. (source: supabase/functions/tgis-generate/index.ts:1948)

## 4.3 Prompt and Provider Execution

- Intent preprocessing uses configured intent model and fallback parser path. (source: supabase/functions/tgis-generate/index.ts:156, supabase/functions/tgis-generate/index.ts:1088)
- Provider call executes against FAL model endpoint. (source: supabase/functions/tgis-generate/index.ts:1926, supabase/functions/tgis-generate/index.ts:2266)

## 4.4 Persistence

- Generation log rows are inserted and updated in `tgis_generation_log`. (source: supabase/functions/tgis-generate/index.ts:2164, supabase/functions/tgis-generate/index.ts:2311)
- Tool run rows are inserted/updated in `tgis_thumb_tool_runs`. (source: supabase/functions/tgis-generate/index.ts:2231, supabase/functions/tgis-generate/index.ts:2377)
- Assets are inserted in `tgis_thumb_assets`. (source: supabase/functions/tgis-generate/index.ts:2282)
- Cost and usage accounting RPCs are emitted after successful generation. (source: supabase/functions/tgis-generate/index.ts:2356, supabase/functions/tgis-generate/index.ts:2365)

## 5. Shared Infrastructure

Thumb tools share utility logic in `_shared/tgisThumbTools.ts`:

- User resolution and admin detection. (source: supabase/functions/_shared/tgisThumbTools.ts:128, supabase/functions/_shared/tgisThumbTools.ts:147)
- Commerce gateway signature validation helper. (source: supabase/functions/_shared/tgisThumbTools.ts:93)
- 1920x1080 normalization/storage pipeline. (source: supabase/functions/_shared/tgisThumbTools.ts:282)
- FAL call helper. (source: supabase/functions/_shared/tgisThumbTools.ts:433)
- Tool run and asset CRUD wrappers. (source: supabase/functions/_shared/tgisThumbTools.ts:503, supabase/functions/_shared/tgisThumbTools.ts:537, supabase/functions/_shared/tgisThumbTools.ts:568)

## 6. Admin Observability

- Admin inference page reads `tgis_generation_log`. (source: src/pages/admin/tgis/AdminTgisInference.tsx:21)
- Admin thumb tools page reads `tgis_thumb_tool_runs`. (source: src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)
- Safety page audits blocked terms and blocked runtime events. (source: src/pages/admin/tgis/AdminTgisSafety.tsx:21, src/pages/admin/tgis/AdminTgisSafety.tsx:25)

## 7. Errors and Recovery

- Commerce failure can trigger auto-reversal in commerce function when dispatch failed pre-cost boundary. (source: supabase/functions/commerce/index.ts:818)
- Client shows insufficient-credit callout and avoids hard crash. (source: src/pages/ThumbGenerator.tsx:314)
- Backend marks generation and tool runs as `failed` on provider or validation errors. (source: supabase/functions/tgis-generate/index.ts:2444, supabase/functions/tgis-generate/index.ts:2459)

## 8. Auth and Access

- Route requires authenticated user (`/app` shell). (source: src/App.tsx:116, src/App.tsx:132)
- Function config has `verify_jwt = false`, but runtime enforces token resolution and role checks. (source: supabase/config.toml:75, supabase/functions/tgis-generate/index.ts:734)

## 9. Maintenance Checklist

1. Keep route, hub registry, and commerce tool code aligned. (source: src/tool-hubs/registry.ts:62, src/tool-hubs/registry.ts:66, src/App.tsx:132)
2. Keep runtime config keys synchronized with DB defaults. (source: supabase/functions/tgis-generate/index.ts:755)
3. Re-validate run/asset schema assumptions after migration changes. (source: supabase/functions/tgis-generate/index.ts:2231, supabase/functions/tgis-generate/index.ts:2282)
4. Re-test insufficient-credit UX whenever commerce response shape changes. (source: src/pages/ThumbGenerator.tsx:314)

## 10. Request and Response Contract (Observed)

Frontend execution payload fields observed for `surprise_gen`:

- `prompt`
- `tags`
- `mood`
- `styleMode`
- `cameraAngle`
- `referenceImageUrl` (optional)

Evidence:
- Frontend payload assembly. (source: src/pages/ThumbGenerator.tsx:295, src/pages/ThumbGenerator.tsx:302)

Backend validation highlights:

- Missing prompt -> `missing_prompt` (400).
- Missing tags -> `missing_tags` (400).
- Invalid reference URL -> `invalid_reference_image_url` (400).
- Blocked prompt -> `prompt_blocked` (400).

Evidence:
- Handler request parse and validation paths. (source: supabase/functions/tgis-generate/index.ts:1975, supabase/functions/tgis-generate/index.ts:1986, supabase/functions/tgis-generate/index.ts:1987, supabase/functions/tgis-generate/index.ts:2041, supabase/functions/tgis-generate/index.ts:2015)

## 11. Prompt Pipeline Detail

Prompt processing pipeline in `tgis-generate`:

1. Sanitize/normalize user text.
2. Run intent preprocessing (`composition_style`, color emphasis, pose, depth).
3. Resolve style profile.
4. Build prompt JSON.
5. Validate prompt JSON contract.
6. Serialize prompt by configured format mode (`json_v1`, `user_first_json`, or text legacy mode).

Evidence:
- Intent/style/prompt builders. (source: supabase/functions/tgis-generate/index.ts:1437, supabase/functions/tgis-generate/index.ts:1698, supabase/functions/tgis-generate/index.ts:1794)
- Prompt format mode and selection. (source: supabase/functions/tgis-generate/index.ts:178, supabase/functions/tgis-generate/index.ts:2081, supabase/functions/tgis-generate/index.ts:2104)
- Prompt validation path. (source: supabase/functions/tgis-generate/index.ts:1850, supabase/functions/tgis-generate/index.ts:2080)

## 12. User Interaction Lifecycle

End-user lifecycle in UI:

1. Fill prompt and optional reference.
2. Optionally rewrite prompt via `tgis-rewrite-prompt`.
3. Execute generation (commerce debit + remote dispatch).
4. Receive generated asset preview and persisted asset id.

Evidence:
- Prompt field and limits. (source: src/pages/ThumbGenerator.tsx:27, src/pages/ThumbGenerator.tsx:449)
- Prompt rewrite call. (source: src/pages/ThumbGenerator.tsx:361)
- Execution and result handling. (source: src/pages/ThumbGenerator.tsx:293, src/pages/ThumbGenerator.tsx:324)

## 13. Discrepancy and Confidence Notes

- Function is configured with `verify_jwt = false` in `supabase/config.toml`, while runtime still requires user resolution and permission checks.

Evidence:
- Config flag and runtime auth check. (source: supabase/config.toml:75, supabase/functions/tgis-generate/index.ts:734, supabase/functions/tgis-generate/index.ts:1972)

`x-doc-confidence: high` for execution and persistence flows.
