# Tool Deep Dive: Reports

## 1. Scope

Reports is the public analytics tool for weekly report discovery and detailed report reading.

- Tool id in hub registry: `reports`. (source: src/tool-hubs/registry.ts:46)
- Hub route target: `/reports`. (source: src/tool-hubs/registry.ts:47)
- Public routes: `/reports` and `/reports/:slug`. (source: src/App.tsx:106, src/App.tsx:107)

## 2. Frontend Pages

## 2.1 Reports List Page

- `ReportsList` links each report card to `/reports/{public_slug}`. (source: src/pages/public/ReportsList.tsx:63)
- List data is loaded through public query path that filters weekly reports to published status. (source: src/hooks/queries/publicQueries.ts:25)

## 2.2 Report View Page

- `ReportView` reads route slug via `useParams`. (source: src/pages/public/ReportView.tsx:194)
- Data hydration uses `dataPublicReportBundle(slug)`. (source: src/pages/public/ReportView.tsx:38, src/pages/public/ReportView.tsx:227)
- Session cache is used for fast reload (`report-cache:{slug}`). (source: src/pages/public/ReportView.tsx:127, src/pages/public/ReportView.tsx:141)

## 2.3 Report Rendering Blocks

- Section framework uses `SectionHeader` and `AiNarrative`. (source: src/pages/public/ReportView.tsx:9, src/pages/public/ReportView.tsx:10)
- Exposure deep-dive is rendered in section 19 and can open detailed exposure explorer component. (source: src/pages/public/ReportView.tsx:808, src/pages/public/ReportView.tsx:856)
- Exposure timeline detail requests `discover-exposure-timeline` on demand. (source: src/pages/public/ReportView.tsx:1443)

## 3. Data API Contract

- `invokeDataApi` sends all operations to `discover-data-api`. (source: src/lib/discoverDataApi.ts:60, src/lib/discoverDataApi.ts:61)
- Public bundle helper wraps operation `public_report_bundle`. (source: src/lib/discoverDataApi.ts:94, src/lib/discoverDataApi.ts:95)
- Admin bundle helper wraps operation `admin_overview_bundle`. (source: src/lib/discoverDataApi.ts:108)

## 4. Backend Flow: `discover-data-api`

## 4.1 Access Model

- Function defines access levels `public | authenticated | admin`. (source: supabase/functions/discover-data-api/index.ts:18)
- `weekly_reports` has special public read constraints. (source: supabase/functions/discover-data-api/index.ts:272)
- Public weekly report reads require `status=published`. (source: supabase/functions/discover-data-api/index.ts:380)

## 4.2 Public Report Bundle

- `runPublicReportBundle` fetches the report row by slug from `weekly_reports` and merges fallback sources when needed. (source: supabase/functions/discover-data-api/index.ts:497, supabase/functions/discover-data-api/index.ts:510, supabase/functions/discover-data-api/index.ts:520)
- In-memory cache exists for bundle responses. (source: supabase/functions/discover-data-api/index.ts:90, supabase/functions/discover-data-api/index.ts:502)

## 4.3 Admin Overview Bundle

- Admin-only snapshot endpoint uses `runAdminOverviewBundle` and access guard. (source: supabase/functions/discover-data-api/index.ts:325, supabase/functions/discover-data-api/index.ts:326)
- Bundle can return memory or snapshot/rpc paths depending on freshness and fallback logic. (source: supabase/functions/discover-data-api/index.ts:330, supabase/functions/discover-data-api/index.ts:366)

## 5. Exposure Timeline Helper Function

- `discover-exposure-timeline` enforces admin/editor gate for unpublished report access paths. (source: supabase/functions/discover-exposure-timeline/index.ts:31, supabase/functions/discover-exposure-timeline/index.ts:44, supabase/functions/discover-exposure-timeline/index.ts:113)
- This function is called from report UI for detailed timeline charting. (source: src/pages/public/ReportView.tsx:1443)

## 6. Auth and Access

- `/reports` and `/reports/:slug` are public routes. (source: src/App.tsx:106, src/App.tsx:107)
- Public list/query layer still enforces published-only data constraints via backend. (source: supabase/functions/discover-data-api/index.ts:380)

## 7. Side Effects

- Normal report view path is read-only for public users.
- Session-level cache writes happen in browser storage for current user session. (source: src/pages/public/ReportView.tsx:141)
- Exposure timeline endpoint reads timeline data; no write path is present in `ReportView`. (source: src/pages/public/ReportView.tsx:1443)

## 8. Failure Modes

- If slug is missing or invalid, report page shows not-found style fallback flow. (source: src/pages/public/ReportView.tsx:209)
- If bundle call fails, UI keeps cache fallback when available and avoids hard crash. (source: src/pages/public/ReportView.tsx:216, src/pages/public/ReportView.tsx:227)
- `discover-data-api` rejects invalid table/column/rpc names with explicit errors. (source: supabase/functions/discover-data-api/index.ts:247, supabase/functions/discover-data-api/index.ts:253, supabase/functions/discover-data-api/index.ts:486)

## 9. Operational Notes

- `discover-data-api` has multiple in-memory caches (token context, role decision, admin bundle, public bundle) that affect perceived freshness. (source: supabase/functions/discover-data-api/index.ts:81, supabase/functions/discover-data-api/index.ts:82, supabase/functions/discover-data-api/index.ts:85, supabase/functions/discover-data-api/index.ts:90)
- Any report schema update in `weekly_reports` requires validation of both list query and bundle merge logic. (source: src/hooks/queries/publicQueries.ts:25, supabase/functions/discover-data-api/index.ts:511)

## 10. Maintenance Checklist

1. Keep route and hub mapping aligned for reports navigation. (source: src/tool-hubs/registry.ts:46, src/App.tsx:106)
2. Keep `public_report_bundle` payload compatible with `ReportView` section render expectations. (source: src/pages/public/ReportView.tsx:491)
3. Re-test published-only filter behavior whenever `weekly_reports` status semantics change. (source: supabase/functions/discover-data-api/index.ts:380)
4. Keep exposure timeline permissions explicit (admin/editor for unpublished internals). (source: supabase/functions/discover-exposure-timeline/index.ts:31)

## 11. Endpoint Contract Summary (Observed)

Endpoints used in this tool:

- `discover-data-api` operation `public_weekly_reports` for list page.
- `discover-data-api` operation `public_report_bundle` for report detail.
- `discover-exposure-timeline` for section-level timeline drilldown.

Evidence:
- Public list query operation key. (source: src/hooks/queries/publicQueries.ts:25)
- Public report bundle call. (source: src/lib/discoverDataApi.ts:94, src/pages/public/ReportView.tsx:227)
- Exposure timeline request. (source: src/pages/public/ReportView.tsx:1443)

## 12. User Journey Summary

1. User opens `/reports`.
2. User chooses a published report card.
3. Report detail page loads cached/session data, then refreshes from `public_report_bundle`.
4. User expands sections including AI narrative and exposure timeline charts.

Evidence:
- List-to-detail route link behavior. (source: src/pages/public/ReportsList.tsx:63)
- Cache restore then fetch strategy. (source: src/pages/public/ReportView.tsx:127, src/pages/public/ReportView.tsx:227)
- Section rendering and exposure block. (source: src/pages/public/ReportView.tsx:808, src/pages/public/ReportView.tsx:856)

## 13. Discrepancy and Confidence Notes

- Public route is open (`/reports`), but report visibility is constrained by backend `status=published` filtering, so access assumptions must be made from backend policy, not route visibility alone.

Evidence:
- Public route declarations. (source: src/App.tsx:106, src/App.tsx:107)
- Backend published filter. (source: supabase/functions/discover-data-api/index.ts:380)

`x-doc-confidence: high` for route/query behavior and read paths.

## 14. Admin/Editorial Interaction Points

Although this tool is public, report lifecycle depends on admin/editor operations:

- Admin uses report management screens under `/admin/reports`.
- Admin overview bundle path exists in `discover-data-api` for editorial workflows.

Evidence:
- Admin report routes. (source: src/App.tsx:142, src/App.tsx:143)
- Admin operation path in data API. (source: src/lib/discoverDataApi.ts:108, supabase/functions/discover-data-api/index.ts:325)

## 15. Not Determined From Code

Not determined from code:

- External publication approval process before report status flips to `published`.
- Whether reports are syndicated outside this platform after publication.

## 16. Change Impact Checklist

When modifying reports rendering:

1. Re-test `/reports` list fetch and slug links.
2. Re-test `/reports/:slug` cache restore + fresh fetch behavior.
3. Re-test exposure timeline fetch path and empty-state rendering.
4. Revalidate published-only data guard in backend operation.

Evidence:
- List and link flow. (source: src/pages/public/ReportsList.tsx:63)
- Cache and fetch flow. (source: src/pages/public/ReportView.tsx:127, src/pages/public/ReportView.tsx:227)
- Exposure timeline loader. (source: src/pages/public/ReportView.tsx:1443)
- Published guard in API. (source: supabase/functions/discover-data-api/index.ts:380)
