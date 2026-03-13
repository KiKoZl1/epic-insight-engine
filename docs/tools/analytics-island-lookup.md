# Tool Deep Dive: Island Lookup

## 1. Scope

Island Lookup is the analytics tool for single-island analysis and side-by-side island comparison, including AI-generated analysis phases.

- Tool id in hub registry: `island-lookup`. (source: src/tool-hubs/registry.ts:38)
- Route target in hub: `/app/island-lookup`. (source: src/tool-hubs/registry.ts:39)
- Route declaration under authenticated app shell. (source: src/App.tsx:121)

## 2. Frontend Flow

## 2.1 Initial and Recent Lookups

- `IslandLookup` loads recent history by invoking `discover-island-lookup` with `mode: "recent"`. (source: src/pages/IslandLookup.tsx:324, src/pages/IslandLookup.tsx:325)
- Recent results are rendered as clickable replay entries. (source: src/pages/IslandLookup.tsx:955, src/pages/IslandLookup.tsx:961, src/pages/IslandLookup.tsx:976)

## 2.2 Primary and Compare Lookup

- Main lookup request is sent to `discover-island-lookup` with `islandCode` and optional `compareCode`. (source: src/pages/IslandLookup.tsx:374, src/pages/IslandLookup.tsx:375)
- Compare mode renders dual KPI and chart panels when second payload exists. (source: src/pages/IslandLookup.tsx:542, src/pages/IslandLookup.tsx:1233)

## 2.3 AI Analysis Layer

- Frontend creates `payloadFingerprint` and requests `discover-island-lookup-ai`. (source: src/pages/IslandLookup.tsx:390, src/pages/IslandLookup.tsx:402)
- If response is baseline and `enriching=true`, frontend polls until enriched response is available or enrichment stops. (source: src/pages/IslandLookup.tsx:422, src/pages/IslandLookup.tsx:432, src/pages/IslandLookup.tsx:451)
- Baseline/enriched state badges are shown in UI. (source: src/pages/IslandLookup.tsx:1135, src/pages/IslandLookup.tsx:1151)

## 3. Backend Flow: `discover-island-lookup`

- Handler declares memory caches for lookup payload and recent history. (source: supabase/functions/discover-island-lookup/index.ts:36, supabase/functions/discover-island-lookup/index.ts:37)
- Function supports `mode: "recent"` retrieval path used by UI. (source: src/pages/IslandLookup.tsx:325)
- Function also handles normal lookup and compare semantics based on request body fields. (source: src/pages/IslandLookup.tsx:375)

## 4. Backend Flow: `discover-island-lookup-ai`

- Cached rows are persisted in `discover_lookup_ai_recent`. (source: supabase/functions/discover-island-lookup-ai/index.ts:545)
- Response normalization differentiates baseline vs enriched payload forms. (source: supabase/functions/discover-island-lookup-ai/index.ts:429, supabase/functions/discover-island-lookup-ai/index.ts:433)
- Fallback insights are generated data-first when external model is unavailable. (source: supabase/functions/discover-island-lookup-ai/index.ts:758, supabase/functions/discover-island-lookup-ai/index.ts:762)
- NVIDIA/OpenRouter style external enrichment path is conditionally executed when key/model path exists. (source: supabase/functions/discover-island-lookup-ai/index.ts:811, supabase/functions/discover-island-lookup-ai/index.ts:830)

## 5. Auth and Access Semantics

- Tool route requires authenticated user via `/app` protected shell. (source: src/App.tsx:116, src/App.tsx:121)
- Functions in `supabase/config.toml` mark lookup handlers with `verify_jwt = false`, so access control relies on internal token checks and runtime logic. (source: supabase/config.toml:9, supabase/config.toml:45)
- AI function includes service-role mode for warm/cache operations. (source: supabase/functions/discover-island-lookup-ai/index.ts:452, supabase/functions/discover-island-lookup-ai/index.ts:460)

## 6. Data Contracts

## 6.1 Input Contract (frontend)

- `islandCode` is required for primary lookup. (source: src/pages/IslandLookup.tsx:374)
- `compareCode` is optional and toggles compare mode. (source: src/pages/IslandLookup.tsx:375, src/pages/IslandLookup.tsx:296)
- AI layer sends `primarySummary`, optional `compareSummary`, and `payloadFingerprint`. (source: src/pages/IslandLookup.tsx:389, src/pages/IslandLookup.tsx:410, src/pages/IslandLookup.tsx:411)

## 6.2 Output Contract (frontend consumption)

Key consumed fields include:
- `metadata` (title/code/category/tags). (source: src/pages/IslandLookup.tsx:249)
- `dailyMetrics` and derived totals/series. (source: src/pages/IslandLookup.tsx:237, src/pages/IslandLookup.tsx:566)
- `discoverySignalsV2` panel insights. (source: src/pages/IslandLookup.tsx:260, src/pages/IslandLookup.tsx:650)
- `competitorsV2` relative positioning. (source: src/pages/IslandLookup.tsx:262, src/pages/IslandLookup.tsx:1786)
- `eventsV2`/metadata events. (source: src/pages/IslandLookup.tsx:238, src/pages/IslandLookup.tsx:730)

## 7. Side Effects and Persistence

- Recent lookup data is persisted and returned through lookup functions. (source: src/pages/IslandLookup.tsx:324, src/pages/IslandLookup.tsx:328)
- AI output cache is written and hit-count updated in `discover_lookup_ai_recent`. (source: supabase/functions/discover-island-lookup-ai/index.ts:602, supabase/functions/discover-island-lookup-ai/index.ts:604)

## 8. Failure Modes

- Compare lookup failures trigger user toast and keep primary data available. (source: src/pages/IslandLookup.tsx:493)
- AI enrichment failures can degrade to baseline/fallback payload and still return a response. (source: supabase/functions/discover-island-lookup-ai/index.ts:758, supabase/functions/discover-island-lookup-ai/index.ts:916)
- Response polling stops when enrichment is no longer active to avoid endless requests. (source: src/pages/IslandLookup.tsx:451, src/pages/IslandLookup.tsx:452)

## 9. Discrepancy and Risk Notes

- `verify_jwt = false` in config plus runtime token logic can confuse maintainers; keep function-level auth checks explicit in docs and tests. (source: supabase/config.toml:9, supabase/config.toml:45, supabase/functions/discover-island-lookup-ai/index.ts:464)
- Service-role prewarm path intentionally uses synthetic user context; do not reuse for user-facing analytics decisions. (source: supabase/functions/discover-island-lookup-ai/index.ts:461)

## 10. Maintenance Checklist

1. Keep hub metadata and route alignment (`id`, `to`, route path) synchronized. (source: src/tool-hubs/registry.ts:38, src/tool-hubs/registry.ts:39, src/App.tsx:121)
2. When changing payload schema, update `buildLookupSummary` and UI chart builders together. (source: src/pages/IslandLookup.tsx:236, src/pages/IslandLookup.tsx:556)
3. Keep AI baseline/enriched compatibility logic backward-safe for cached rows. (source: supabase/functions/discover-island-lookup-ai/index.ts:391)
4. Revalidate recent lookup and cache retention settings when tuning memory TTL env values. (source: supabase/functions/discover-island-lookup/index.ts:67, supabase/functions/discover-island-lookup/index.ts:71)

## 11. Endpoint Contract Summary (Observed)

Primary endpoints used by this tool:

- `discover-island-lookup`
  - main lookup
  - compare lookup
  - recent mode
- `discover-island-lookup-ai`
  - baseline analysis
  - async enrichment/polling updates

Evidence:
- Recent lookup request call. (source: src/pages/IslandLookup.tsx:324)
- Main lookup payload. (source: src/pages/IslandLookup.tsx:374, src/pages/IslandLookup.tsx:375)
- AI call payload. (source: src/pages/IslandLookup.tsx:402, src/pages/IslandLookup.tsx:410)

## 12. User Journey Summary

1. User enters island code (and optional compare code).
2. Tool fetches core analytics payload.
3. Tool requests AI summary and initially receives baseline.
4. Tool polls until enriched analysis is available or enrichment stops.
5. User can reopen recent lookups from history list.

Evidence:
- Lookup trigger flow. (source: src/pages/IslandLookup.tsx:374)
- AI baseline/enriched polling loop. (source: src/pages/IslandLookup.tsx:422, src/pages/IslandLookup.tsx:432, src/pages/IslandLookup.tsx:451)
- Recent replay interaction. (source: src/pages/IslandLookup.tsx:955, src/pages/IslandLookup.tsx:976)

## 13. Discrepancy and Confidence Notes

- Function config shows `verify_jwt = false` for lookup endpoints, while runtime logic still applies token/role handling and service-mode branches; this should remain explicitly documented to avoid incorrect assumptions.

Evidence:
- Config flags. (source: supabase/config.toml:9, supabase/config.toml:45)
- Runtime token/service role logic. (source: supabase/functions/discover-island-lookup-ai/index.ts:452, supabase/functions/discover-island-lookup-ai/index.ts:464)

`x-doc-confidence: high` for UI flow and endpoint usage.

## 14. Operational Debug Checklist

For investigation of lookup incidents:

1. Confirm base lookup endpoint response for same island code.
2. Confirm AI endpoint returns baseline payload.
3. Verify enrichment poll path transitions to enriched/fallback without infinite loop.
4. Inspect cache key behavior (`payloadFingerprint`) for stale reuse.

Evidence:
- Lookup and AI call points. (source: src/pages/IslandLookup.tsx:374, src/pages/IslandLookup.tsx:402)
- Poll termination conditions. (source: src/pages/IslandLookup.tsx:451, src/pages/IslandLookup.tsx:452)
- Fingerprint usage in AI request. (source: src/pages/IslandLookup.tsx:390, src/pages/IslandLookup.tsx:411)

## 15. Not Determined From Code

Not determined from code:

- Formal TTL policy for long-term persistence of recent lookup records.
- Business priority rules for enrichment queue under high load.

## 16. Change Impact Checklist

Before shipping lookup changes:

1. Validate single-island lookup response shape in UI charts.
2. Validate compare mode response shape and dual rendering.
3. Validate baseline AI response fallback and enrichment polling stop conditions.
4. Validate recent-history list replay behavior.

Evidence:
- Lookup and compare rendering usage. (source: src/pages/IslandLookup.tsx:542, src/pages/IslandLookup.tsx:1233)
- Baseline/enriched status UI and polling. (source: src/pages/IslandLookup.tsx:422, src/pages/IslandLookup.tsx:451, src/pages/IslandLookup.tsx:1135)
- Recent replay UI. (source: src/pages/IslandLookup.tsx:955, src/pages/IslandLookup.tsx:976)
