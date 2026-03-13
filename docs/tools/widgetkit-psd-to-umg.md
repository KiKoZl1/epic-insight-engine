# Tool Deep Dive: WidgetKit PSD to UMG (`psd_to_umg`)

## 1. Scope

This document covers the WidgetKit PSD to UMG tool implemented in UEFN Toolkit.

- Tool route: `/app/widgetkit/psd-umg`. (source: src/App.tsx:127)
- Hub route: `/app/widgetkit`. (source: src/App.tsx:125)
- Tool registry id: `psd-umg`. (source: src/tool-hubs/registry.ts:100)
- Commerce code: `psd_to_umg`. (source: src/tool-hubs/registry.ts:104, src/lib/commerce/toolCosts.ts:6)

## 2. User and Route Flow

## 2.1 Route and Guard Chain

Request path from browser to page:

1. User enters `/app/widgetkit/psd-umg`.
2. Route is nested under `/app`.
3. `/app` is wrapped by `ProtectedRoute`.
4. Unauthenticated users are redirected to `/auth`.

Evidence:
- Nested route structure. (source: src/App.tsx:116, src/App.tsx:125, src/App.tsx:127)
- Protected redirect behavior. (source: src/components/ProtectedRoute.tsx:4, src/components/ProtectedRoute.tsx:15)

## 2.2 Page Composition

- Page container is `PsdToUmgPage`.
- Main conversion UI is `PsdToUmgTool`.
- Page includes breadcrumb/back link to WidgetKit hub.

Evidence:
- Page layout and mounted tool component. (source: src/pages/widgetkit/PsdToUmgPage.tsx:7, src/pages/widgetkit/PsdToUmgPage.tsx:23)

## 3. Frontend Behavior

## 3.1 Local State Model

The component tracks:

- Parse/conversion status (`idle`, `parsing`, `preview`, `ready`, and error states).
- Parsed PSD JSON.
- Layer summary.
- Generated UMG output text.
- Tool history list (up to 10 recent entries in UI state).
- Credit error state for insufficient balance UX.

Evidence:
- Status union and state declarations. (source: src/components/widgetkit/PsdToUmgTool.tsx:19, src/components/widgetkit/PsdToUmgTool.tsx:67)

## 3.2 Input Validation and Parse Stage

The tool validates and parses client-side:

- Accepts only `.psd` input from file picker and drag-drop.
- Validates PSD signature bytes (`8BPS`).
- Enforces dimension limit (`8192x8192`) and layer limit (hard cap `500`, warning at `200`).
- Normalizes PSD tree into internal layer model.

Evidence:
- File input constraint. (source: src/components/widgetkit/PsdToUmgTool.tsx:277)
- Parser signature validation. (source: src/lib/widgetkit/psd-parser.ts:26, src/lib/widgetkit/psd-parser.ts:28)
- Max limits. (source: src/lib/widgetkit/psd-parser.ts:3, src/lib/widgetkit/psd-parser.ts:4, src/lib/widgetkit/psd-parser.ts:117, src/lib/widgetkit/psd-parser.ts:123)
- Layer normalization pipeline. (source: src/lib/widgetkit/psd-parser.ts:43, src/lib/widgetkit/psd-parser.ts:98, src/lib/widgetkit/psd-parser.ts:120)

## 3.3 UMG Generation Stage

After successful parse:

- Conversion runs locally through `generateBeginObject`.
- Output contains generated `Begin Object` blocks for Canvas/Text/Image objects.
- Optional `includeTint` injects generated color palette into image brush output.

Evidence:
- Generation call from UI action. (source: src/components/widgetkit/PsdToUmgTool.tsx:148)
- Generator entrypoint. (source: src/lib/widgetkit/umg-generator.ts:63)
- Include tint behavior. (source: src/lib/widgetkit/umg-generator.ts:134)

## 4. Commerce and Credits

## 4.1 Execution Contract

Before local generation, frontend debits credits using commerce API:

- Calls `executeCommerceTool` with `toolCode: "psd_to_umg"`.
- Sends payload fields: `file_name`, `total_layers`, `include_tint`.
- Uses idempotency and optimistic credit UI updates in commerce client.

Evidence:
- Tool execute call and payload. (source: src/components/widgetkit/PsdToUmgTool.tsx:138, src/components/widgetkit/PsdToUmgTool.tsx:141)
- Execute client contract. (source: src/lib/commerce/client.ts:176, src/lib/commerce/client.ts:194)
- Optimistic and rollback events. (source: src/lib/commerce/client.ts:185, src/lib/commerce/client.ts:217)

## 4.2 Local Dispatch Semantics

Commerce backend marks WidgetKit tools as local dispatch:

- `psd_to_umg` does not invoke a separate edge function.
- Backend still records successful debit/attempt path.
- Response includes `dispatch: "client_local"`.

Evidence:
- Local branch for WidgetKit tool codes. (source: supabase/functions/commerce/index.ts:761)
- Success payload with `dispatch`. (source: supabase/functions/commerce/index.ts:786)

## 4.3 Cost Source

- Frontend fallback default: `2` credits.
- Runtime override can come from commerce catalog.

Evidence:
- Default map value. (source: src/lib/commerce/toolCosts.ts:16)
- Catalog fetch endpoint and decode path. (source: src/lib/commerce/toolCosts.ts:91, src/lib/commerce/toolCosts.ts:113)

## 5. Persistence Model (`widgetkit_history`)

## 5.1 Frontend Read/Write

History operations are done through Supabase client:

- List by tool id.
- Insert generated entry (name, data JSON, metadata JSON).
- Delete selected history entry.

Evidence:
- History API wrapper methods. (source: src/lib/widgetkit/history.ts:6, src/lib/widgetkit/history.ts:18, src/lib/widgetkit/history.ts:39)
- Save call from tool flow. (source: src/components/widgetkit/PsdToUmgTool.tsx:155)

## 5.2 Database Contract

`widgetkit_history` schema constraints:

- `tool` must be one of `psd-umg` or `umg-verse`.
- RLS restricts normal users to their own rows.
- Trigger keeps most recent 10 rows per `(user_id, tool)`.

Evidence:
- Table definition and check constraint. (source: supabase/migrations/20260305010000_widgetkit_history.sql:3, supabase/migrations/20260305010000_widgetkit_history.sql:6)
- Trim trigger logic. (source: supabase/migrations/20260305010000_widgetkit_history.sql:16, supabase/migrations/20260305010000_widgetkit_history.sql:30, supabase/migrations/20260305010000_widgetkit_history.sql:38)
- RLS and policies. (source: supabase/migrations/20260305010000_widgetkit_history.sql:43, supabase/migrations/20260305010000_widgetkit_history.sql:46, supabase/migrations/20260305010000_widgetkit_history.sql:52, supabase/migrations/20260305010000_widgetkit_history.sql:58)

## 6. Error and Recovery Paths

## 6.1 Parse/Format Errors

Common parse errors:

- `error_format`
- `error_empty`
- `error_dimensions`
- `error_too_many_layers`

Evidence:
- Error states and mapper. (source: src/components/widgetkit/PsdToUmgTool.tsx:24, src/components/widgetkit/PsdToUmgTool.tsx:29)
- Parser throw paths. (source: src/lib/widgetkit/psd-parser.ts:30, src/lib/widgetkit/psd-parser.ts:116, src/lib/widgetkit/psd-parser.ts:117, src/lib/widgetkit/psd-parser.ts:123)

## 6.2 Credit Failure and Reversal

If local generation fails after debit:

- Tool attempts `reverseCommerceOperation` using operation id.
- Failure in reversal is handled as best effort without crash.
- Insufficient-credit payload is mapped to dedicated callout.

Evidence:
- Reverse call on error path. (source: src/components/widgetkit/PsdToUmgTool.tsx:173, src/components/widgetkit/PsdToUmgTool.tsx:175)
- Insufficient credit mapper usage. (source: src/components/widgetkit/PsdToUmgTool.tsx:183, src/components/widgetkit/PsdToUmgTool.tsx:185)

## 7. Security and Access

- Tool is available only in authenticated route tree (`/app`).
- Data persistence uses table-level RLS tied to `auth.uid()`.
- Admin/editor read policy exists for operational inspection.

Evidence:
- Auth route wrapper. (source: src/App.tsx:116)
- RLS user policies. (source: supabase/migrations/20260305010000_widgetkit_history.sql:46, supabase/migrations/20260305010000_widgetkit_history.sql:52, supabase/migrations/20260305010000_widgetkit_history.sql:58)
- Admin/editor select policy. (source: supabase/migrations/20260305010000_widgetkit_history.sql:64)

## 8. API Surface (Observed)

Commerce endpoint used:

- Method: `POST`
- Path: `/functions/v1/commerce/tools/execute`
- Auth: Bearer token required by commerce client.
- Request body fields observed:
  - `tool_code` (`psd_to_umg`)
  - `payload.file_name`
  - `payload.total_layers`
  - `payload.include_tint`
  - `request_id`
  - `idempotency_key`

Evidence:
- Request builder and auth header. (source: src/lib/commerce/client.ts:39, src/lib/commerce/client.ts:53, src/lib/commerce/client.ts:191, src/lib/commerce/client.ts:194)

`x-doc-status: partial` for full response schema because this document is tool-focused and canonical endpoint schemas are documented in `docs/openapi-backend-b-commerce.yaml`.

## 9. Discrepancy and Risk Notes

- WidgetKit tool execution is billed through backend but conversion output is generated client-side. Operationally this means logic/versioning can drift by frontend release, not edge runtime release.

Evidence:
- Local generation call in UI. (source: src/components/widgetkit/PsdToUmgTool.tsx:148)
- Commerce local dispatch branch. (source: supabase/functions/commerce/index.ts:761)

## 10. Maintenance Checklist

1. Keep route id, nav id, and commerce tool code aligned. (source: src/navigation/config.ts:116, src/tool-hubs/registry.ts:100, src/lib/commerce/toolCosts.ts:6)
2. Re-test parser limits whenever PSD parser dependency or limits change. (source: src/lib/widgetkit/psd-parser.ts:3, src/lib/widgetkit/psd-parser.ts:104)
3. Revalidate reversal flow on billing API changes. (source: src/components/widgetkit/PsdToUmgTool.tsx:175, src/lib/commerce/client.ts:225)
4. Keep table trim trigger and UI history length assumptions aligned (`10`). (source: src/components/widgetkit/PsdToUmgTool.tsx:167, supabase/migrations/20260305010000_widgetkit_history.sql:30)
