# Tool Deep Dive: WidgetKit UMG to Verse (`umg_to_verse`)

## 1. Scope

This document covers the WidgetKit UMG to Verse tool implemented in UEFN Toolkit.

- Tool route: `/app/widgetkit/umg-verse`. (source: src/App.tsx:128)
- Hub route: `/app/widgetkit`. (source: src/App.tsx:125)
- Tool registry id: `umg-verse`. (source: src/tool-hubs/registry.ts:108)
- Commerce code: `umg_to_verse`. (source: src/tool-hubs/registry.ts:112, src/lib/commerce/toolCosts.ts:7)

## 2. User and Route Flow

## 2.1 Route and Guard Chain

Execution path:

1. User navigates to `/app/widgetkit/umg-verse`.
2. Route is nested under `/app`.
3. `/app` is gated by `ProtectedRoute`.
4. Missing session redirects to `/auth`.

Evidence:
- Route tree. (source: src/App.tsx:116, src/App.tsx:125, src/App.tsx:128)
- Protected gate behavior. (source: src/components/ProtectedRoute.tsx:4, src/components/ProtectedRoute.tsx:15)

## 2.2 Page Composition

- Page component `UmgToVersePage` renders route shell and back navigation.
- Main converter component is `UmgToVerseTool`.

Evidence:
- Page assembly. (source: src/pages/widgetkit/UmgToVersePage.tsx:7, src/pages/widgetkit/UmgToVersePage.tsx:23)

## 3. Frontend Behavior

## 3.1 State Model

Main runtime states:

- `empty`, `parsing`, `preview`, `ready`, `no_fields`, `error_format`.
- Parsed widget representation (`ParsedWidget`).
- Generated Verse output bundle.
- History entries and load state.
- Insufficient-credit model for callout.

Evidence:
- Status union and state declarations. (source: src/components/widgetkit/UmgToVerseTool.tsx:17, src/components/widgetkit/UmgToVerseTool.tsx:58)

## 3.2 Parse Stage

The parser validates and extracts `VerseClassFields` from uploaded `.uasset`:

- Accepts only `.uasset` file extension from input/drop.
- Verifies package signature/magic tag.
- Decodes binary payload as `latin1`.
- Parses `Name`, `Type`, and related metadata fields.
- Groups fields by type for generation UI and output.

Evidence:
- File input filter. (source: src/components/widgetkit/UmgToVerseTool.tsx:277)
- Signature checks. (source: src/lib/widgetkit/uasset-parser.ts:3, src/lib/widgetkit/uasset-parser.ts:31)
- Decoder and parser flow. (source: src/lib/widgetkit/uasset-parser.ts:106, src/lib/widgetkit/uasset-parser.ts:107, src/lib/widgetkit/uasset-parser.ts:66, src/lib/widgetkit/uasset-parser.ts:99)
- Type grouping. (source: src/lib/widgetkit/uasset-parser.ts:20, src/lib/widgetkit/uasset-parser.ts:109)

## 3.3 Generation Stage

After parse and field validation:

- Runs `generateVerseOutput(parsedWidget)` on client.
- Emits manager file name/code and `ui_core.verse` template content.
- Creates per-field setter/update helpers and event stubs.

Evidence:
- Generation call from tool flow. (source: src/components/widgetkit/UmgToVerseTool.tsx:143)
- Generator return fields. (source: src/lib/widgetkit/verse-generator.ts:220, src/lib/widgetkit/verse-generator.ts:223)
- Event/setter generation logic. (source: src/lib/widgetkit/verse-generator.ts:75, src/lib/widgetkit/verse-generator.ts:119, src/lib/widgetkit/verse-generator.ts:132)

## 4. Commerce and Credits

## 4.1 Execution Contract

Before generating Verse output, frontend calls commerce execution:

- `toolCode: "umg_to_verse"`.
- Payload includes `widget_name` and `fields_total`.
- Client uses optimistic debit and rollback handling.

Evidence:
- Execute call and payload. (source: src/components/widgetkit/UmgToVerseTool.tsx:134, src/components/widgetkit/UmgToVerseTool.tsx:137)
- Optimistic debit/rollback events. (source: src/lib/commerce/client.ts:185, src/lib/commerce/client.ts:217)

## 4.2 Local Dispatch Semantics

Commerce backend behavior for this tool:

- Debits credits through standard execution path.
- Marks usage attempt success with upstream `client_local`.
- Returns success payload without calling external tool function.

Evidence:
- Local execution branch covering `umg_to_verse`. (source: supabase/functions/commerce/index.ts:761)
- Usage attempt success record for local tools. (source: supabase/functions/commerce/index.ts:762)

## 4.3 Cost Source

- Frontend fallback default cost: `2`.
- Runtime cost can be overridden through backend catalog.

Evidence:
- Default cost map. (source: src/lib/commerce/toolCosts.ts:17)
- Catalog request path. (source: src/lib/commerce/toolCosts.ts:91)

## 5. History Persistence Model

## 5.1 UI Calls

The tool reads/writes/deletes history through shared WidgetKit history client:

- `listWidgetKitHistory("umg-verse")`
- `saveWidgetKitHistory(...)`
- `deleteWidgetKitHistory(id)`

Evidence:
- Tool calls. (source: src/components/widgetkit/UmgToVerseTool.tsx:74, src/components/widgetkit/UmgToVerseTool.tsx:150, src/components/widgetkit/UmgToVerseTool.tsx:236)
- Shared history functions. (source: src/lib/widgetkit/history.ts:6, src/lib/widgetkit/history.ts:18, src/lib/widgetkit/history.ts:39)

## 5.2 Database Rules

`widgetkit_history` schema and policy behavior:

- Tool discriminator check constraint includes `umg-verse`.
- Trigger trims entries to 10 per user/tool.
- RLS enforces owner-only insert/delete/select for standard users.

Evidence:
- Tool constraint. (source: supabase/migrations/20260305010000_widgetkit_history.sql:6)
- Trim logic and trigger. (source: supabase/migrations/20260305010000_widgetkit_history.sql:16, supabase/migrations/20260305010000_widgetkit_history.sql:30, supabase/migrations/20260305010000_widgetkit_history.sql:38)
- Policies. (source: supabase/migrations/20260305010000_widgetkit_history.sql:46, supabase/migrations/20260305010000_widgetkit_history.sql:52, supabase/migrations/20260305010000_widgetkit_history.sql:58)

## 6. Error and Recovery Paths

## 6.1 Parse and Semantic Empty Cases

Observed conditions:

- `error_format` when file/signature parsing fails.
- `no_fields` when source lacks `VerseClassFields` or parsed field list is empty.

Evidence:
- Parser rejection paths and signature checks. (source: src/lib/widgetkit/uasset-parser.ts:32, src/lib/widgetkit/uasset-parser.ts:38, src/lib/widgetkit/uasset-parser.ts:100)
- No-fields flow. (source: src/components/widgetkit/UmgToVerseTool.tsx:116, src/components/widgetkit/UmgToVerseTool.tsx:223)

## 6.2 Debit Reversal on Local Generation Failure

If error occurs after billing:

- UI attempts `reverseCommerceOperation`.
- Reversal failure is best effort and does not hard-fail UI.
- Insufficient credit payload is mapped to dedicated callout.

Evidence:
- Reversal path. (source: src/components/widgetkit/UmgToVerseTool.tsx:170, src/components/widgetkit/UmgToVerseTool.tsx:172)
- Insufficient-credit mapping. (source: src/components/widgetkit/UmgToVerseTool.tsx:180, src/components/widgetkit/UmgToVerseTool.tsx:182)

## 7. Security and Access

- Route is inside authenticated app tree (`/app`).
- History table uses RLS to bind rows to `auth.uid()`.
- Admin/editor users have explicit read policy for support/inspection.

Evidence:
- App route guard. (source: src/App.tsx:116)
- User policies. (source: supabase/migrations/20260305010000_widgetkit_history.sql:46, supabase/migrations/20260305010000_widgetkit_history.sql:52, supabase/migrations/20260305010000_widgetkit_history.sql:58)
- Admin/editor policy. (source: supabase/migrations/20260305010000_widgetkit_history.sql:64)

## 8. API Surface (Observed)

Commerce endpoint used by this tool:

- Method: `POST`
- Path: `/functions/v1/commerce/tools/execute`
- Body fields:
  - `tool_code` = `umg_to_verse`
  - `payload.widget_name`
  - `payload.fields_total`
  - `request_id`
  - `idempotency_key`

Evidence:
- Request builder and execute call. (source: src/lib/commerce/client.ts:190, src/lib/commerce/client.ts:194, src/components/widgetkit/UmgToVerseTool.tsx:135, src/components/widgetkit/UmgToVerseTool.tsx:137)

`x-doc-status: partial` for complete schema details because authoritative endpoint response map is maintained in `docs/openapi-backend-b-commerce.yaml`.

## 9. Discrepancy and Risk Notes

- Backend billing and usage accounting happen server-side, but transformation logic is fully client-side. Version drift risk is tied to frontend deployment cadence.

Evidence:
- Client-side generator call. (source: src/components/widgetkit/UmgToVerseTool.tsx:143)
- Commerce local dispatch branch. (source: supabase/functions/commerce/index.ts:761)

## 10. Maintenance Checklist

1. Keep nav and registry entries aligned with route paths. (source: src/navigation/config.ts:128, src/tool-hubs/registry.ts:108, src/App.tsx:128)
2. Revalidate parser when Unreal package patterns evolve. (source: src/lib/widgetkit/uasset-parser.ts:3, src/lib/widgetkit/uasset-parser.ts:67)
3. Validate generated Verse templates when field typing rules change. (source: src/lib/widgetkit/verse-generator.ts:25, src/lib/widgetkit/verse-generator.ts:34)
4. Keep history limit assumptions aligned between trigger and UI slices (`10`). (source: supabase/migrations/20260305010000_widgetkit_history.sql:30, src/components/widgetkit/UmgToVerseTool.tsx:164)
