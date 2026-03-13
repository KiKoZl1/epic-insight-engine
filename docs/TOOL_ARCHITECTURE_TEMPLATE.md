# Tool Architecture Template (UEFN Toolkit)

This is the implementation-derived template for adding or refactoring tools in UEFN Toolkit.

It is both:

- A build checklist for engineering.
- A documentation checklist for keeping `docs/tools/*` complete.

## 1. Canonical Build Path for a New Tool

## 1.1 Product Registration Layer

Add tool metadata to registry:

- `id`
- `to` route
- i18n keys (`titleKey`, `descriptionKey`)
- `icon`
- `toolCode` (if commerce-billed)
- `requiresAuth`

Evidence:
- Registry type contracts. (source: src/tool-hubs/registry.ts:5, src/tool-hubs/registry.ts:9)
- Existing tool examples. (source: src/tool-hubs/registry.ts:61, src/tool-hubs/registry.ts:95, src/tool-hubs/registry.ts:100)

## 1.2 Route Integration Layer

Place route in `src/App.tsx` under the correct guard:

- Public route under smart/public shell.
- Auth tool route under `/app` + `ProtectedRoute`.
- Admin operation route under `/admin` + `AdminRoute` if needed.

Evidence:
- Public routes. (source: src/App.tsx:103)
- Auth routes under protected shell. (source: src/App.tsx:116)
- Admin routes and guard. (source: src/App.tsx:140, src/components/AdminRoute.tsx:4)

## 1.3 Navigation Layer

If the tool should appear in topbar/mobile navigation:

1. Add nav item in `src/navigation/config.ts`.
2. Assign group/category.
3. Map protected behavior (`requiresAuthPrompt`) if public discoverability is desired.
4. Map nav item to `toolCode` if credit chip is needed.

Evidence:
- Nav item definitions. (source: src/navigation/config.ts:220)
- Auth prompt flag usage. (source: src/navigation/config.ts:230)
- Nav-to-tool code mapping. (source: src/lib/commerce/toolCosts.ts:152)

## 2. Frontend Tool Module Contract

Use this contract for each tool page/component.

## 2.1 Minimum Module Surface

- A page wrapper component in `src/pages/...`.
- A main tool component in `src/components/...` or feature folder.
- Stable user-action states (`idle`, `loading`, `ready`, `error` variants).
- Explicit error handling path for async failures.

Evidence:
- Page wrapper pattern (WidgetKit pages). (source: src/pages/widgetkit/PsdToUmgPage.tsx:7, src/pages/widgetkit/UmgToVersePage.tsx:7)
- Stateful tool component examples. (source: src/components/widgetkit/PsdToUmgTool.tsx:67, src/components/widgetkit/UmgToVerseTool.tsx:58)

## 2.2 Commerce Hook-In (If Billed)

Expected flow:

1. Resolve tool cost (`useToolCosts` / `getCost`).
2. Render cost badge/chip.
3. Execute `executeCommerceTool`.
4. Handle insufficient credits with dedicated UI callout.
5. Reverse operation if tool fails after debit and operation id exists.

Evidence:
- Cost usage and badge rendering. (source: src/components/widgetkit/PsdToUmgTool.tsx:65, src/components/widgetkit/PsdToUmgTool.tsx:245)
- Execute call. (source: src/components/widgetkit/PsdToUmgTool.tsx:138, src/components/widgetkit/UmgToVerseTool.tsx:134)
- Insufficient credit callout pattern. (source: src/components/widgetkit/PsdToUmgTool.tsx:17, src/components/widgetkit/UmgToVerseTool.tsx:15)
- Reverse on failure. (source: src/components/widgetkit/PsdToUmgTool.tsx:175, src/components/widgetkit/UmgToVerseTool.tsx:172)

## 2.3 Data Persistence (Optional but Common)

If tool keeps user history/state:

- Create table via migration.
- Add RLS policies.
- Add typed client helper in `src/lib/<domain>/`.
- Enforce deterministic row bounds when needed (trigger or query limit).

Evidence:
- WidgetKit history migration and policies. (source: supabase/migrations/20260305010000_widgetkit_history.sql:3, supabase/migrations/20260305010000_widgetkit_history.sql:43, supabase/migrations/20260305010000_widgetkit_history.sql:46)
- Client helper pattern. (source: src/lib/widgetkit/history.ts:6)

## 3. Backend Execution Pattern Options

There are two observed execution classes.

## 3.1 Remote Edge Dispatch (Thumb Tools Pattern)

Pattern:

1. Commerce debits credits.
2. Commerce dispatches tool to mapped edge function.
3. Tool function persists run and output metadata.

Evidence:
- Tool dispatch map for remote tools. (source: supabase/functions/commerce/index.ts:36)
- Debit RPC. (source: supabase/functions/commerce/index.ts:735)
- Dispatch invocation. (source: supabase/functions/commerce/index.ts:803)

## 3.2 Client-Local Execution (WidgetKit Pattern)

Pattern:

1. Commerce debits credits.
2. Commerce marks usage success as `client_local`.
3. Client performs transformation logic and optionally reverses debit on local failure.

Evidence:
- Local execution branch for `psd_to_umg` and `umg_to_verse`. (source: supabase/functions/commerce/index.ts:761)
- Frontend local generators. (source: src/lib/widgetkit/umg-generator.ts:63, src/lib/widgetkit/verse-generator.ts:95)

## 4. Security and Authorization Template

For every tool, document these checks:

1. Route-level access gate.
2. Backend auth mode (`verify_jwt`) and runtime checks.
3. RLS policies on persisted tables.
4. Role-based admin access for observability or support operations.

Evidence examples:
- Route guard checks. (source: src/components/ProtectedRoute.tsx:15, src/components/AdminRoute.tsx:16)
- Function JWT flags. (source: supabase/config.toml:75, supabase/config.toml:126)
- RLS sample policy set. (source: supabase/migrations/20260305010000_widgetkit_history.sql:46)

## 5. Observability Template

When tool is remote or high-impact, ensure it has:

- Run table or generation log.
- Admin read path (screen or query).
- Error state persistence (status + code + message).

Evidence:
- TGIS run logs and admin pages. (source: supabase/functions/tgis-generate/index.ts:2231, src/pages/admin/tgis/AdminTgisThumbTools.tsx:35)

For local-only tools:

- Server-side usage accounting is available from commerce ledger.
- Detailed client transform trace logging is not determined from code.

Evidence:
- Commerce usage attempts and ledger retrieval. (source: supabase/functions/commerce/index.ts:762, supabase/functions/commerce/index.ts:676)

## 6. Documentation Deliverables for Every Tool

Create one file in `docs/tools/<tool>.md` with at least:

1. Tool scope and route.
2. Frontend interaction flow.
3. Backend/commerce contract.
4. Auth rules.
5. Side effects (DB writes, external calls).
6. Error map and recovery behavior.
7. Discrepancy notes.
8. Maintenance checklist.

Index update requirements:

- Add link to `docs/tools/README.md`.
- Add link to `docs/TOOLS_CATALOG.md`.
- Ensure `docs/SYSTEM_COVERAGE_MATRIX.md` references new tool doc.

## 7. Quality Gate Checklist Before Merge

1. Route exists and is reachable from intended nav/hub entry.
2. Tool code is added to `CommerceToolCode` if billed.
3. Cost defaults and catalog key mapping are present.
4. Backend function path (or explicit local execution rule) is documented.
5. Error UX includes insufficient credit and generic fallback.
6. RLS/policies exist for any new persisted table.
7. `docs/tools/*.md` file is created and linked from indexes.
8. OpenAPI is updated if new HTTP endpoint was added.

Evidence baseline:
- `CommerceToolCode` union and defaults. (source: src/lib/commerce/toolCosts.ts:1, src/lib/commerce/toolCosts.ts:11)
- Commerce execution endpoint. (source: supabase/functions/commerce/index.ts:1587)
- OpenAPI artifacts in docs. (source: docs/openapi-backend-a.yaml:1, docs/openapi-backend-b-commerce.yaml:1)

## 8. Copy/Paste Documentation Skeleton

Use this skeleton in new tool docs:

```md
# Tool Deep Dive: <Tool Name> (`<tool_code_if_any>`)

## 1. Scope
- Route(s): ...
- Hub/registry id: ...
- Tool code: ...

## 2. User and Route Flow
- Guard chain ...
- Page composition ...

## 3. Frontend Behavior
- Inputs/state/actions ...

## 4. Backend and Commerce
- Endpoint(s) ...
- Debit/dispatch path ...

## 5. Data Side Effects
- Tables written/read ...
- External services called ...

## 6. Auth and Security
- Route auth ...
- Function auth ...
- RLS ...

## 7. Error and Recovery
- Error codes/states ...
- Reversal/fallback behavior ...

## 8. Discrepancy Notes
- Frontend/backend mismatches ...

## 9. Maintenance Checklist
1. ...
```

## 9. Not Determined From Code

Not determined from code:

- Mandatory minimum line count policy per tool document.
- Whether local-only tools must be migrated to backend execution in roadmap.

Do not infer these items without explicit repository evidence.
