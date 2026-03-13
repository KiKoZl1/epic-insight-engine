# Frontend Documentation

## Estrutura de Rotas do Cliente
- Públicas: `/`, `/discover`, `/island`, `/reports`, `/reports/:slug`, `/tools/analytics`, `/tools/thumb-tools`, `/tools/widgetkit`. (fonte: src/App.tsx:102)
- Auth: `/auth`. (fonte: src/App.tsx:113)
- Protegidas (`ProtectedRoute`): `/app` e subrotas de dashboard, analytics, billing, credits, widgetkit e thumb-tools. (fonte: src/App.tsx:116, src/components/ProtectedRoute.tsx:15)
- Admin (`AdminRoute`): `/admin` e subrotas dppi/tgis/commerce/reports/etc. (fonte: src/App.tsx:140, src/components/AdminRoute.tsx:16)

## Auth Guards
- `ProtectedRoute`: exige usuário autenticado.
- `AdminRoute`: exige `isAdmin || isEditor`.
(fonte: src/components/ProtectedRoute.tsx:15, src/components/AdminRoute.tsx:16)

## Componentes Principais
- `src/App.tsx`: composição da aplicação e roteamento principal.
- `src/hooks/useAuth.tsx`: sessão, sign-in/sign-up/sign-out, cache de role.
- `src/pages/public/DiscoverLive.tsx`: consumo de dados públicos discover.
- `src/pages/public/ReportView.tsx`: visualização detalhada de relatórios públicos.
- `src/pages/admin/AdminOverview.tsx`: painel operacional/admin.
- `src/pages/thumb-tools/EditStudioPage.tsx`: fluxo de edição de thumbnail.

## Estado Global
- State manager dedicado (Redux/Zustand/Pinia): Não determinado a partir do código.
- Estado global efetivo: `AuthContext` + React Query (`QueryClientProvider`). (fonte: src/hooks/useAuth.tsx:19, src/App.tsx:74)

## Chamadas de API do Cliente
- Gateway de dados: `discover-data-api` com operações `select|update|delete|upsert|rpc|public_report_bundle|admin_overview_bundle`. (fonte: src/lib/discoverDataApi.ts:60)
- Funções públicas discover: `discover-rails-resolver`, `discover-island-page`. (fonte: src/hooks/queries/publicQueries.ts:63)
- Funções admin e ferramentas: chamadas diretas para `discover-*`, `dppi-*`, `tgis-*`, `commerce`. (fonte: src/pages/admin/AdminOverview.tsx:639)

## Discrepâncias Frontend x Backend
- Nenhuma discrepância nominal obrigatória detectada entre nomes invocados no frontend e funções presentes em `supabase/functions` nesta execução.
- `x-doc-status: incomplete` para compatibilidade de schema detalhado request/response em cada chamada.
