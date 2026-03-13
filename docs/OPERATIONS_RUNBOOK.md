# Operations Runbook

Runbook de operação contínua (monitoramento, jobs, troubleshooting e rotina de manutenção).

## 1. Comandos de rotina
### 1.1 App/frontend
```bash
npm run dev
npm run lint
npm run test
npm run test:e2e
```

Evidência: `package.json:7`.

### 1.2 Ralph / memória operacional
```bash
npm run ralph:local
npm run ralph:loop
npm run ralph:memory:ingest
npm run ralph:memory:query
```

Evidência: `package.json:18`.

### 1.3 Migrações e dados
```bash
npm run migration:set-target -- -ProjectRef <ref> -SupabaseUrl <url> -PublishableKey <key>
npm run migration:export:tables
scripts\run-sql.bat -Query "select now();"
```

Evidência: `package.json:22`, `scripts/sql.ps1:55`.

## 2. Health checks mínimos
## 2.1 Frontend + rotas
- `/`
- `/discover`
- `/reports`
- `/app` (auth)
- `/admin` (role admin/editor)

Evidência:
- rotas em `App.tsx`. (fonte: `src/App.tsx:103`)
- smoke e2e para rotas públicas/protegidas. (fonte: `e2e/navigation-smoke.spec.ts:3`)

## 2.2 Commerce
- `GET /functions/v1/commerce/catalog/tool-costs`
- `GET /functions/v1/commerce/me/credits`
- `POST /functions/v1/commerce/tools/execute` (cenário controlado)

Evidência: `supabase/functions/commerce/index.ts:1563`.

## 2.3 Discover gateway
- Validar operação `select` via `discover-data-api`.
- Em data split habilitado, validar bridge headers/owner.

Evidência:
- API gateway op payload. (fonte: `src/lib/discoverDataApi.ts:60`)
- bridge logic. (fonte: `supabase/functions/_shared/dataBridge.ts:36`)

## 3. Jobs e tarefas operacionais
### 3.1 Jobs internos commerce
- `POST /functions/v1/commerce/internal/jobs/weekly-release`
- `POST /functions/v1/commerce/internal/jobs/reconcile`

Exigem `x-commerce-internal-secret` ou admin.

Evidência: `supabase/functions/commerce/index.ts:1701`.

### 3.2 Admin cron discover
- Função `discover-cron-admin` com modos `list/set/pause/resume`.

Evidência: `supabase/functions/discover-cron-admin/index.ts:108`.

### 3.3 Workers ML
- TGIS preflight e bootstrap via `scripts/setup_tgis.sh`.
- DPPI/TGIS unidades systemd em `ml/*/deploy/systemd`.

Evidência: `scripts/setup_tgis.sh:176`.

## 4. Alertas e sintomas comuns
### 4.1 Frontend redireciona `/admin` para `/app`
Possível causa:
- role ainda não hidratada ou usuário sem role admin/editor.

Evidência:
- regra no `AdminRoute`. (fonte: `src/components/AdminRoute.tsx:16`)
- helper e2e espera ativação de role admin. (fonte: `e2e/helpers/adminAuth.ts:63`)

### 4.2 Falha em execução de tool por crédito
Possível causa:
- `INSUFFICIENT_CREDITS` (saldo insuficiente)
- falha upstream tgis

Evidência:
- erro de crédito e recommended action. (fonte: `supabase/functions/commerce/index.ts:747`)
- retorno de erro upstream em dispatch. (fonte: `supabase/functions/commerce/index.ts:829`)

### 4.3 Falha em webhook Stripe
Possível causa:
- `STRIPE_WEBHOOK_SECRET` ausente
- assinatura inválida/timestamp fora de tolerância

Evidência:
- checagens webhook. (fonte: `supabase/functions/commerce/index.ts:1180`, `supabase/functions/commerce/index.ts:1183`)

### 4.4 SQL runner não funciona
Possível causa:
- `SUPABASE_DB_URL` ausente
- `psql` não instalado

Evidência: `scripts/sql.ps1:58`, `scripts/sql.ps1:64`.

## 5. Observabilidade prática
## 5.1 E2E de navegação e hubs
- `e2e/navigation-smoke.spec.ts`
- `e2e/tool-hubs.spec.ts`

## 5.2 Perf suites disponíveis
- `e2e/perf-api-map.spec.ts`
- `e2e/perf-island-progressive.spec.ts`
- `e2e/perf-routes-all.spec.ts`
- `e2e/perf-real-traffic-admin.spec.ts`

(fonte: árvore `e2e/`)

## 6. Procedimento de incident response (curto)
1. Confirmar escopo (frontend, function específica, banco, stripe).
2. Validar variáveis de ambiente relacionadas.
3. Reproduzir com endpoint mínimo e idempotency key nova.
4. Se impacto financeiro, pausar operações internas sensíveis e usar admin endpoints para auditoria (`/admin/user/*`).
5. Aplicar correção, rodar smoke/e2e, redeploy controlado.

Base técnica:
- idempotency em commerce. (fonte: `src/lib/commerce/client.ts:57`, `supabase/functions/commerce/index.ts:721`)
- admin financial endpoints. (fonte: `supabase/functions/commerce/index.ts:1662`)

## 7. Mudanças seguras (playbook)
### Backend function change
- atualizar função
- revisar envs
- atualizar OpenAPI
- testar endpoint isolado
- rodar smoke e2e

### Frontend route/tool change
- atualizar `src/App.tsx` + `src/tool-hubs/registry.ts`
- validar auth guards
- validar tool cost mapping
- rodar `test` + `test:e2e`

Evidência:
- rotas. (fonte: `src/App.tsx:103`)
- tool registry. (fonte: `src/tool-hubs/registry.ts:24`)
- costs map. (fonte: `src/lib/commerce/toolCosts.ts:152`)

## 8. Itens sem definição operacional explícita
- SLO/SLA oficial versionado no repositório.
- Stack de observabilidade externa (Datadog, Grafana, etc.) configurada via código.

Status: **Não determinado a partir do código**.
