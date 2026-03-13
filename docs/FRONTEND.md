# Frontend Documentation

Comprehensive frontend technical documentation for routes, guards, state, API integration, and operational discrepancies.

## 1. Scope and Runtime

Frontend stack:
- React 18 + React Router
- TanStack Query for async cache/fetch orchestration
- Supabase client for auth and edge function calls

Evidence:
- Query client setup and router structure. (source: src/App.tsx:74)
- Supabase auth/context usage. (source: src/hooks/useAuth.tsx:49)

## 2. Route Topology

## 2.1 Public Routes

Declared public routes:
- `/`
- `/discover`
- `/island`
- `/reports`
- `/reports/:slug`
- `/tools/analytics`
- `/tools/thumb-tools`
- `/tools/widgetkit`
- `/auth`

Evidence:
- Public route declarations. (source: src/App.tsx:102)

## 2.2 Authenticated App Routes (`/app/*`)

Protected by `ProtectedRoute`.

Route map:
- `/app`
- `/app/analytics-tools`
- `/app/projects/:id`
- `/app/projects/:id/reports/:reportId`
- `/app/island-lookup`
- `/app/billing`
- `/app/credits`
- `/app/thumb-tools/*`
- `/app/widgetkit/*`

Evidence:
- App route subtree. (source: src/App.tsx:116)

## 2.3 Admin Routes (`/admin/*`)

Protected by `AdminRoute` and includes:
- overview, reports, exposure, intel, panels
- DPPI admin pages
- TGIS admin pages
- Commerce admin page

Evidence:
- Admin route subtree. (source: src/App.tsx:140)

## 3. Guard Model

## 3.1 `ProtectedRoute`

Behavior:
- while auth is loading: render spinner
- if no user: redirect to `/auth`
- else: render children

Evidence:
- Guard implementation. (source: src/components/ProtectedRoute.tsx:4)

## 3.2 `AdminRoute`

Behavior:
- while loading: render spinner
- if no user: redirect `/auth`
- if user lacks admin/editor role: redirect `/app`
- else: render admin content

Evidence:
- Admin guard implementation. (source: src/components/AdminRoute.tsx:4)

## 4. Authentication and Role Resolution

Auth provider behavior includes:
- session/user subscription via `supabase.auth.onAuthStateChange`
- role lookup in `user_roles`
- role cache in memory + localStorage with 5 minute TTL
- role shortcuts for `isAdmin` and `isEditor`

Evidence:
- Role cache constants and storage key. (source: src/hooks/useAuth.tsx:20)
- Role query against `user_roles`. (source: src/hooks/useAuth.tsx:80)
- `isAdmin` and `isEditor` derivation. (source: src/hooks/useAuth.tsx:187)

## 5. Navigation and Tool Surface

## 5.1 Navigation Domains

Navigation config defines domain groups:
- platform
- analytics
- workspace
- thumb tools
- widget kit
- admin

Evidence:
- Navigation section config. (source: src/navigation/config.ts:270)

## 5.2 Tool Hub Registry

Tool hubs:
- `analyticsTools`
- `thumbTools`
- `widgetKit`

Each tool contains:
- route
- icon
- optional commerce tool code
- auth requirement flag

Evidence:
- Registry root. (source: src/tool-hubs/registry.ts:23)
- Thumb tool code mapping. (source: src/tool-hubs/registry.ts:55)

## 6. Major Frontend Components and Modules

The following modules are core to system behavior and maintenance.

## 6.1 `src/App.tsx`

Responsibilities:
- route tree composition
- lazy loading of major pages/layouts
- query client bootstrap

Evidence:
- Route declarations and query client. (source: src/App.tsx:74)

## 6.2 `src/hooks/useAuth.tsx`

Responsibilities:
- auth session lifecycle
- role hydration and cache
- sign-in, sign-up, sign-out actions

Evidence:
- Provider internals and methods. (source: src/hooks/useAuth.tsx:49)

## 6.3 `src/lib/discoverDataApi.ts`

Responsibilities:
- unified frontend gateway to `discover-data-api`
- op-based wrappers (`select`, `update`, `delete`, `upsert`, `rpc`, bundles)

Evidence:
- invoke wrapper and exported API helpers. (source: src/lib/discoverDataApi.ts:60)

## 6.4 `src/lib/commerce/client.ts`

Responsibilities:
- direct HTTP client to `commerce` backend
- idempotency/device fingerprint headers
- optimistic credit UI synchronization
- commerce endpoint wrappers for user/admin operations

Evidence:
- request builder and endpoint wrappers. (source: src/lib/commerce/client.ts:68)
- optimistic debit events. (source: src/lib/commerce/client.ts:176)

## 6.5 `src/features/tgis-thumb-tools/ThumbToolsProvider.tsx`

Responsibilities:
- thumb asset history state
- selected current asset persistence in sessionStorage
- optimistic delete with rollback on failure

Evidence:
- provider state and delete flow. (source: src/features/tgis-thumb-tools/ThumbToolsProvider.tsx:31)

## 6.6 `src/pages/admin/AdminOverview.tsx`

Responsibilities:
- operational admin dashboard for discover + ralph + pipelines
- calls `dataAdminOverviewBundle` and protected function invocations

Evidence:
- bundle usage and protected invoke helper. (source: src/pages/admin/AdminOverview.tsx:620)
- Ralph telemetry fetch. (source: src/pages/admin/AdminOverview.tsx:863)

## 7. Global State Model

## 7.1 Primary State Carriers

There is no Redux/Zustand/Pinia store in current code.

Global state is handled by:
- React Context (`AuthContext`) for identity/role state
- TanStack Query for server state caching
- local component state for page-level workflows

Evidence:
- Auth context declaration. (source: src/hooks/useAuth.tsx:19)
- Query client provider at app root. (source: src/App.tsx:85)

## 7.2 Persistence Strategy

- role cache persisted in localStorage
- selected thumb asset persisted in sessionStorage
- tool cost catalog cache persisted in localStorage

Evidence:
- Role storage methods. (source: src/hooks/useAuth.tsx:23)
- Thumb session key and persistence. (source: src/features/tgis-thumb-tools/ThumbToolsProvider.tsx:29)
- Tool cost local cache key. (source: src/lib/commerce/toolCosts.ts:29)

## 8. Frontend API Call Inventory

## 8.1 `discover-data-api` wrappers

Frontend operation wrappers:
- `dataSelect`
- `dataUpdate`
- `dataDelete`
- `dataUpsert`
- `dataRpc`
- `dataPublicReportBundle`
- `dataAdminOverviewBundle`

Evidence:
- exported wrapper functions. (source: src/lib/discoverDataApi.ts:69)

## 8.2 Direct Supabase function invocations (selected high-impact)

Public and app pages:
- `discover-rails-resolver` (live discover rails)
- `discover-island-page` (island view + summary)
- `discover-island-lookup` and `discover-island-lookup-ai`
- `discover-panel-timeline`
- `discover-exposure-timeline`

Evidence:
- Public query hooks. (source: src/hooks/queries/publicQueries.ts:43)
- Island lookup page calls. (source: src/pages/IslandLookup.tsx:324)

Admin pages:
- `dppi-health`, `dppi-refresh-batch`, `dppi-train-dispatch`, `dppi-release-set`
- `tgis-health`, `tgis-admin-start-training`, `tgis-admin-training-run-action`, `tgis-admin-promote-model`, `tgis-admin-rollback-model`, `tgis-admin-delete-model`, `tgis-admin-refresh-dataset`, `tgis-admin-sync-manifest`
- discover admin flows (`discover-report-rebuild`, `discover-report-ai`, `discover-exposure-report`, `discover-exposure-collector`)

Evidence:
- DPPI admin calls. (source: src/pages/admin/dppi/AdminDppiOverview.tsx:27)
- TGIS admin calls. (source: src/pages/admin/tgis/AdminTgisModels.tsx:86)
- Discover admin report editor calls. (source: src/pages/admin/AdminReportEditor.tsx:133)

Thumb tools and widget tools:
- execute via commerce client (`/tools/execute`)
- rollback via commerce client (`/tools/reverse`)
- asset deletion via `tgis-delete-asset`

Evidence:
- Commerce tool execute wrapper usage in pages. (source: src/pages/ThumbGenerator.tsx:15)
- Direct delete function invoke. (source: src/features/tgis-thumb-tools/ThumbToolsProvider.tsx:165)

## 8.3 Commerce direct HTTP calls

Frontend does not call `supabase.functions.invoke("commerce")`.

It calls REST endpoints directly:
- `/functions/v1/commerce/me/credits`
- `/functions/v1/commerce/me/ledger`
- `/functions/v1/commerce/tools/execute`
- `/functions/v1/commerce/tools/reverse`
- `/functions/v1/commerce/billing/*`
- `/functions/v1/commerce/admin/*`

Evidence:
- URL construction in client. (source: src/lib/commerce/client.ts:92)
- Endpoint wrappers. (source: src/lib/commerce/client.ts:155)

## 9. Frontend Error Handling Patterns

Common strategy:
- catch and toast in page-level actions
- decode backend `error` fields where available
- optimistic UI rollback on tool execute failure

Evidence:
- Billing/Credits action error toasts. (source: src/pages/BillingPage.tsx:76)
- Optimistic rollback in commerce client. (source: src/lib/commerce/client.ts:217)
- Thumb asset delete rollback. (source: src/features/tgis-thumb-tools/ThumbToolsProvider.tsx:175)

## 10. Frontend-Backend Discrepancies

### 10.1 `tgis-rewrite-prompt` mismatch

Frontend calls `tgis-rewrite-prompt`, but function is not declared in `supabase/config.toml`.

Evidence:
- Frontend call. (source: src/pages/ThumbGenerator.tsx:361)
- Config list omission. (source: supabase/config.toml:3)
- Function file exists. (source: supabase/functions/tgis-rewrite-prompt/index.ts:63)

`DISCREPANCY: endpoint may fail in environments where undeclared functions are not deployed.`

### 10.2 Backend functions not directly invoked from frontend

Several functions are configured but used indirectly (cron/internal/worker) or not used by frontend directly.

Examples:
- `dppi-worker-heartbeat`
- `tgis-training-webhook`
- `discover-cron-admin`

Evidence:
- Config list. (source: supabase/config.toml:3)
- Frontend invoke inventory. (source: src/hooks/queries/publicQueries.ts:63)

`DISCREPANCY: documentation must separate user-facing calls from internal control-plane calls.`

## 11. Admin Center Frontend Coverage

Admin center pages include dedicated surfaces for:
- discover operations
- DPPI operations
- TGIS training/model controls
- commerce admin controls
- Ralph telemetry and operational tables

Evidence:
- Admin route map in app router. (source: src/App.tsx:140)
- Ralph fetch and state mapping in admin overview. (source: src/pages/admin/AdminOverview.tsx:863)
- Commerce admin UI actions. (source: src/pages/admin/AdminCommerce.tsx:205)

## 12. LLM/ML Frontend Surfaces

### 12.1 DPPI (DDPI) admin pages

- `/admin/dppi`
- `/admin/dppi/models`
- `/admin/dppi/training`
- `/admin/dppi/inference`
- `/admin/dppi/drift`
- `/admin/dppi/calibration`
- `/admin/dppi/releases`
- `/admin/dppi/feedback`

Evidence:
- DPPI route declarations. (source: src/App.tsx:147)

### 12.2 TGIS LLM and training pages

- `/admin/tgis`
- `/admin/tgis/clusters`
- `/admin/tgis/dataset`
- `/admin/tgis/training`
- `/admin/tgis/models`
- `/admin/tgis/inference`
- `/admin/tgis/thumb-tools`
- `/admin/tgis/costs`
- `/admin/tgis/safety`

Evidence:
- TGIS route declarations. (source: src/App.tsx:155)

### 12.3 Thumb tool user pages (generation/edit)

- generate tool page
- edit studio page
- camera control page
- layer decomposition page

Evidence:
- Thumb route declarations. (source: src/App.tsx:130)

## 13. Frontend Documentation Confidence

High confidence:
- route topology
- guard logic
- auth context behavior
- concrete endpoint invocation points

Medium confidence:
- exact payload schemas for dynamic edge function responses without shared TypeScript contracts

Low confidence:
- long-tail nested fields of backend responses where frontend treats data as `any`

Evidence:
- dynamic `any` usage in admin pages and data bundles. (source: src/pages/admin/AdminOverview.tsx:585)

## 14. Maintenance Checklist for Frontend Changes

When changing frontend route/API behavior, verify:
1. route declarations in `src/App.tsx`
2. nav item exposure and visibility in `src/navigation/config.ts`
3. auth role assumptions in `useAuth` and route guards
4. backend endpoint availability in `supabase/config.toml`
5. docs consistency in `docs/BACKEND_A.md`, `docs/BACKEND_B_COMMERCE.md`, and OpenAPI files

Evidence:
- Router source of truth. (source: src/App.tsx:100)
- Nav source of truth. (source: src/navigation/config.ts:5)
- Backend function registry source. (source: supabase/config.toml:3)
