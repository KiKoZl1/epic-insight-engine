# Developer Guide

Guia de manutenção para qualquer dev entrar no projeto e operar com segurança.

## 1. Stack e runtime
- Frontend: React 18 + Vite + TypeScript + React Router + React Query. (fonte: `package.json:69`, `src/App.tsx:5`)
- Client Supabase: `@supabase/supabase-js` com persistência de sessão no `localStorage`. (fonte: `src/integrations/supabase/client.ts:11`)
- Backend: Supabase Edge Functions por domínio (`discover`, `dppi`, `tgis`, `commerce`). (fonte: `supabase/config.toml:3`)
- Banco: Postgres via migrations SQL em `supabase/migrations`. (fonte: estrutura de diretórios)
- ML pipelines: Python em `ml/dppi` e `ml/tgis`. (fonte: árvore `ml/**`)

## 2. Serviços e responsabilidades
### 2.1 Frontend (`src/`)
- Composição de providers, layouts e árvore de rotas centralizada em `src/App.tsx`. (fonte: `src/App.tsx:84`)
- Auth context em `src/hooks/useAuth.tsx` com role cache TTL de 5 minutos. (fonte: `src/hooks/useAuth.tsx:20`)
- Guards:
  - `ProtectedRoute` exige usuário autenticado. (fonte: `src/components/ProtectedRoute.tsx:15`)
  - `AdminRoute` exige `admin/editor`. (fonte: `src/components/AdminRoute.tsx:16`)

### 2.2 Backend Discover/DPPI/TGIS
- Cada function expõe endpoint `/functions/v1/<name>`.
- `discover-data-api` é um façade para operações de dados com payload `{ op, payload }`. (fonte: `src/lib/discoverDataApi.ts:60`)
- `verify_jwt` varia por função no deploy config, exigindo leitura endpoint-a-endpoint. (fonte: `supabase/config.toml:4`)

### 2.3 Backend Commerce
- Router HTTP interno em uma única Edge Function (`commerce`). (fonte: `supabase/functions/commerce/index.ts:1555`)
- Responsável por:
  - catálogo/custos
  - consulta de créditos/ledger
  - débito/reversão de operações
  - checkout Stripe (assinatura + packs)
  - webhook provider
  - admin financeiro e jobs internos

(fonte: `supabase/functions/commerce/index.ts:1563`)

### 2.4 ML / Workers
- DPPI: treinamento/inferência/drift/monitoring em `ml/dppi/**`. (fonte: árvore `ml/dppi`)
- TGIS: pipelines de clusterização/training/runtime worker em `ml/tgis/**`. (fonte: árvore `ml/tgis`)
- Script de bootstrap de worker TGIS com preflight e opcional AI Toolkit: `scripts/setup_tgis.sh`. (fonte: `scripts/setup_tgis.sh:176`)

## 3. Fluxos principais do produto
### 3.1 Fluxo público (sem login)
- Usuário acessa `/`, `/discover`, `/reports`, hubs públicos de tools.
- Subtools protegidas disparam prompt de auth em vez de acesso direto.

Evidência:
- Rotas públicas em `App.tsx`. (fonte: `src/App.tsx:103`)
- Teste e2e de hub público e prompt de auth. (fonte: `e2e/tool-hubs.spec.ts:5`)

### 3.2 Fluxo autenticado (workspace)
- Usuário autenticado acessa `/app` e subrotas analíticas e ferramentas.
- Auth e role são hidratados a partir de `supabase.auth` + tabela `user_roles`.

Evidência:
- Rotas app. (fonte: `src/App.tsx:116`)
- Carga de role via `from("user_roles")`. (fonte: `src/hooks/useAuth.tsx:81`)

### 3.3 Fluxo admin
- Admin/editor acessa `/admin/*` (Discover, DPPI, TGIS, Commerce).

Evidência:
- Rotas admin. (fonte: `src/App.tsx:140`)
- Regra de acesso em `AdminRoute`. (fonte: `src/components/AdminRoute.tsx:16`)

## 4. Mapa de módulos frontend
### 4.1 Navegação e hubs
- Config de navegação: `src/navigation/config.ts`.
- Catálogo de hubs e tool routes: `src/tool-hubs/registry.ts`.
- Hubs:
  - `analyticsTools`
  - `thumbTools`
  - `widgetKit`

(fonte: `src/tool-hubs/registry.ts:4`)

### 4.2 Integração API
- Data API abstraction: `src/lib/discoverDataApi.ts`.
- Commerce client: `src/lib/commerce/client.ts`.
- Custos de tools + cache local: `src/lib/commerce/toolCosts.ts`.

(fonte: `src/lib/discoverDataApi.ts:60`, `src/lib/commerce/client.ts:68`, `src/lib/commerce/toolCosts.ts:29`)

### 4.3 Páginas de domínio
- Public: `src/pages/public/*`
- App: `src/pages/*`
- Admin: `src/pages/admin/*`
- Thumb tools: `src/pages/thumb-tools/*`
- WidgetKit: `src/pages/widgetkit/*`

(fonte: imports em `src/App.tsx:17`)

## 5. Mapa de módulos backend
### 5.1 Discover
Principais funções:
- `discover-data-api`
- `discover-collector`
- `discover-report-rebuild`
- `discover-report-ai`
- `discover-panel-timeline`
- `discover-rails-resolver`

(fonte: `supabase/functions/*` e `supabase/config.toml`)

### 5.2 DPPI
Principais funções:
- `dppi-health`
- `dppi-refresh-batch`
- `dppi-train-dispatch`
- `dppi-release-set`
- `dppi-worker-heartbeat`

(fonte: `supabase/config.toml:60`)

### 5.3 TGIS
Principais funções:
- `tgis-generate`
- `tgis-edit-studio`
- `tgis-camera-control`
- `tgis-layer-decompose`
- `tgis-skins-search`
- `tgis-admin-*`

(fonte: `supabase/config.toml:75`)

### 5.4 Commerce
- Ver detalhes completos em `docs/PAYMENTS_GATEWAY.md` e `docs/BACKEND_B_COMMERCE.md`.

## 6. Setup de dev (passo a passo)
1. `npm install`
2. `cp .env.example .env`
3. preencher variáveis mínimas (`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)
4. opcional: `npm run migration:set-target -- -ProjectRef ...`
5. `npm run dev`

Evidência:
- Scripts npm. (fonte: `package.json:7`)
- Variáveis obrigatórias e exemplos. (fonte: `.env.example:1`)
- Script de target/migração. (fonte: `package.json:22`)

## 7. Testes e validação
### 7.1 Frontend
- `npm run test`
- `npm run test:watch`

### 7.2 E2E
- `npm run test:e2e`
- `npm run test:e2e:headed`
- `npm run test:e2e:report`

Evidência:
- scripts. (fonte: `package.json:12`)

### 7.3 Cenários cobertos na suite
- smoke de navegação pública/protegida
- comportamento dos hubs de ferramentas
- perf routes / perf admin flows

Evidência:
- arquivos em `e2e/`. (fonte: `e2e/navigation-smoke.spec.ts:1`, `e2e/tool-hubs.spec.ts:1`)

## 8. SQL e dados
### 8.1 Executar SQL remoto
```powershell
scripts\run-sql.bat -Query "select now();"
scripts\run-sql.bat -File supabase\migrations\20260312083000_commerce_foundation_v1.sql
```

Evidência:
- SQL runner exige `SUPABASE_DB_URL`. (fonte: `scripts/sql.ps1:58`)

### 8.2 Export de tabelas
```bash
npm run migration:export:tables
```
- Exporta CSVs para `migration_artifacts/exports`.

Evidência:
- script e outputDir. (fonte: `package.json:23`, `scripts/export_supabase_tables.mjs:133`)

## 9. Segurança e autorização (visão prática)
- App roles: `admin`, `editor`, `client`. (fonte: `src/hooks/useAuth.tsx:5`)
- Admin navigation/UI depende de role hidratada do backend.
- Commerce reforça autorização em backend (não depende só de `verify_jwt`).

Evidência:
- `requireFinancialAdmin` e checks de rota. (fonte: `supabase/functions/commerce/index.ts:280`, `supabase/functions/commerce/index.ts:1662`)

## 10. Manutenção contínua
### 10.1 Quando mexer em frontend
- Atualizar rotas em `src/App.tsx`.
- Validar nav/hubs (`src/navigation/config.ts`, `src/tool-hubs/registry.ts`).
- Rodar `npm run test` e `npm run test:e2e`.

### 10.2 Quando mexer em functions
- Atualizar função em `supabase/functions/<name>/index.ts`.
- Garantir env vars correspondentes em `.env.example` quando necessário.
- Se endpoint mudou, atualizar OpenAPI (`docs/openapi-backend-a.yaml` ou `docs/openapi-backend-b-commerce.yaml`).

### 10.3 Quando mexer em cobrança
- Revisar:
  - `src/lib/commerce/client.ts`
  - `src/lib/commerce/toolCosts.ts`
  - `supabase/functions/commerce/index.ts`
- Validar idempotência + reversão automática em falha.

Evidência:
- `Idempotency-Key` no client e debit/reverse no backend. (fonte: `src/lib/commerce/client.ts:57`, `supabase/functions/commerce/index.ts:735`)

## 11. O que ainda não está explicitamente codificado
- Pipeline único de deploy de frontend para um provedor específico.
- Política oficial de rollback de banco em documento único.

Status nestes pontos: **Não determinado a partir do código**.

## 12. Leituras obrigatórias relacionadas
- `README.md` (onboarding geral)
- `docs/TOOLS_CATALOG.md`
- `docs/PAYMENTS_GATEWAY.md`
- `docs/DEPLOYMENT_RUNBOOK.md`
- `docs/OPERATIONS_RUNBOOK.md`
- `docs/BACKEND_A.md`
- `docs/BACKEND_B_COMMERCE.md`
- `docs/DATABASE.md`
