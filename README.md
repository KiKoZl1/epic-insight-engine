# Epic Insight Engine

Guia técnico completo para onboarding, operação e manutenção do projeto.

## 1) O que este projeto é
Epic Insight Engine é um webapp React + Supabase que combina:
- Observabilidade e analytics de dados Discover (painéis públicos, relatórios e lookup).
- Ferramentas de criação (Thumb Tools + WidgetKit) com cobrança por créditos.
- Backoffice administrativo para Discover, DPPI, TGIS e Commerce.

Evidência:
- Rotas públicas, app e admin em `src/App.tsx`. (fonte: `src/App.tsx:103`)
- Tool hubs e mapeamento de ferramentas em `src/tool-hubs/registry.ts`. (fonte: `src/tool-hubs/registry.ts:24`)
- Gateway de créditos e Stripe em `supabase/functions/commerce/index.ts`. (fonte: `supabase/functions/commerce/index.ts:717`)

## 2) Arquitetura resumida
### Frontend
- React 18 + Vite + React Router + React Query.
- App server local em porta `8080`.

Evidência:
- Stack e scripts. (fonte: `package.json:7`)
- Porta dev Vite. (fonte: `vite.config.ts:9`)
- Providers principais (`QueryClientProvider`, rotas, auth). (fonte: `src/App.tsx:85`)

### Backend
- Supabase Edge Functions por domínio (`discover-*`, `dppi-*`, `tgis-*`, `commerce`).
- `discover-data-api` atua como gateway de operações de dados (`select/update/delete/upsert/rpc`).
- `commerce` atua como gateway de créditos, checkout e webhooks.

Evidência:
- Lista de funções e `verify_jwt`. (fonte: `supabase/config.toml:3`)
- Gateway discover data API. (fonte: `src/lib/discoverDataApi.ts:60`)
- Rotas commerce. (fonte: `supabase/functions/commerce/index.ts:1563`)

### Banco de dados
- Schema app em migrations SQL (`supabase/migrations`).
- Bridge opcional para segundo projeto Supabase (data split).

Evidência:
- URL DB e bridge vars. (fonte: `.env.example:12`)
- Lógica bridge (`DATA_SUPABASE_URL`, `INTERNAL_BRIDGE_SECRET`). (fonte: `supabase/functions/_shared/dataBridge.ts:36`)

## 3) Estrutura do repositório
- `src/`: frontend, rotas e integração supabase.
- `supabase/functions/`: backend serverless.
- `supabase/migrations/`: schema e evolução de banco.
- `ml/dppi` e `ml/tgis`: pipelines/workers de ML.
- `scripts/`: operação local, SQL, tuning e utilitários.
- `e2e/`: suíte Playwright.

Evidência:
- Arquivos e pastas no workspace. (fonte: árvore do repositório)

## 4) Setup local completo
### 4.1 Pré-requisitos
- Node.js + npm
- Supabase CLI (via `npx supabase@latest ...`)
- psql (para `scripts/sql.ps1`)

Evidência:
- Comandos npm disponíveis. (fonte: `package.json:6`)
- Uso explícito de Supabase CLI por script operacional. (fonte: `scripts/set-discover-metrics-profile.ps1:126`)
- Dependência de psql para SQL runner. (fonte: `scripts/sql.ps1:64`)

### 4.2 Variáveis de ambiente
1. Copie `.env.example` para `.env`.
2. Preencha no mínimo:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Para commerce (Stripe):
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_*`
- `COMMERCE_GATEWAY_SECRET`
- `COMMERCE_INTERNAL_SECRET`

Evidência:
- Todas as chaves listadas em `.env.example`. (fonte: `.env.example:1`)

### 4.3 Ajustar target de projeto Supabase (opcional)
Use o script:
```powershell
npm run migration:set-target -- -ProjectRef <ref> -SupabaseUrl https://<ref>.supabase.co -PublishableKey <anon>
```
Esse script atualiza `.env` e `supabase/config.toml` com backup.

Evidência:
- Atualização de `.env` e `project_id`. (fonte: `scripts/migration-set-target.ps1:60`)

### 4.4 Rodar localmente
```bash
npm install
npm run dev
```
App local: `http://localhost:8080`.

Evidência:
- Script `dev`. (fonte: `package.json:7`)
- Porta configurada. (fonte: `vite.config.ts:9`)

## 5) Testes e qualidade
### Unit/integração frontend
```bash
npm run test
npm run test:watch
```

### E2E Playwright
```bash
npm run test:e2e
npm run test:e2e:headed
npm run test:e2e:report
```

Observação: suite e2e sobe o app em `127.0.0.1:4173` para os testes.

Evidência:
- Scripts de teste. (fonte: `package.json:12`)
- Config Playwright/webServer. (fonte: `playwright.config.ts:16`)
- Exemplos de smoke/tool hubs. (fonte: `e2e/navigation-smoke.spec.ts:3`, `e2e/tool-hubs.spec.ts:3`)

## 6) Ferramentas do produto (visão rápida)
### Analytics Tools
- Island Analytics (`/app`)
- Island Lookup (`/app/island-lookup`)
- Reports (`/reports`)

### Thumb Tools
- Generate (`surprise_gen`)
- Edit Studio (`edit_studio`)
- Camera Control (`camera_control`)
- Layer Decomposition (`layer_decomposition`)

### WidgetKit
- PSD -> UMG (`psd_to_umg`)
- UMG -> Verse (`umg_to_verse`)

Evidência:
- Catálogo de tool hubs e `toolCode`. (fonte: `src/tool-hubs/registry.ts:55`)
- Custos padrão por tool. (fonte: `src/lib/commerce/toolCosts.ts:11`)

## 7) Gateway de pagamento e créditos (resumo)
Fluxo simplificado:
1. Front chama `/functions/v1/commerce/tools/execute` com `Idempotency-Key`.
2. Commerce garante conta, debita crédito e registra operação.
3. Para `psd_to_umg`/`umg_to_verse`, execução é `client_local`.
4. Para demais tools, despacha para `tgis-*` correspondente.
5. Em falha qualificável, auto-reverte operação.

Checkout Stripe:
- Assinatura: `/billing/subscription/checkout`
- Packs: `/billing/packs/{packCode}/checkout`
- Webhook: `/billing/webhooks/provider` com verificação de assinatura.

Evidência:
- Fluxo execute/debit/dispatch/reversal. (fonte: `supabase/functions/commerce/index.ts:717`)
- Mapping tool->função tgis. (fonte: `supabase/functions/commerce/index.ts:36`)
- Stripe checkout e webhook verify. (fonte: `supabase/functions/commerce/index.ts:375`, `supabase/functions/commerce/index.ts:1179`)

## 8) Deploy e release (resumo)
### Frontend
```bash
npm run build
npm run preview
```
Saída em `dist` (padrão Vite).

### Supabase Functions
Exemplo explícito documentado nos scripts:
```bash
npx supabase@latest functions deploy discover-collector --project-ref <ref>
```

### Supabase Secrets
Exemplo via script de perfil:
```bash
npx supabase@latest secrets set ... --project-ref <ref>
```

Evidência:
- Build scripts. (fonte: `package.json:8`)
- Deploy command de função. (fonte: `scripts/set-discover-metrics-profile.ps1:145`)
- Secrets set. (fonte: `scripts/set-discover-metrics-profile.ps1:126`)

## 9) Operação diária e manutenção
### Scripts úteis
- `npm run ralph:local`
- `npm run ralph:loop`
- `npm run ralph:memory:ingest`
- `npm run ralph:memory:query`
- `npm run migration:export:tables`

Evidência:
- Scripts no `package.json`. (fonte: `package.json:18`)

### SQL remoto
```powershell
scripts\run-sql.bat -Query "select now();"
scripts\run-sql.bat -File supabase\migrations\<file>.sql
```

Evidência:
- Wrapper e SQL runner. (fonte: `scripts/run-sql.bat:1`, `scripts/sql.ps1:69`)

## 10) Documentação detalhada
- [`docs/DEVELOPER_GUIDE.md`](docs/DEVELOPER_GUIDE.md)
- [`docs/TOOLS_CATALOG.md`](docs/TOOLS_CATALOG.md)
- [`docs/PAYMENTS_GATEWAY.md`](docs/PAYMENTS_GATEWAY.md)
- [`docs/DEPLOYMENT_RUNBOOK.md`](docs/DEPLOYMENT_RUNBOOK.md)
- [`docs/OPERATIONS_RUNBOOK.md`](docs/OPERATIONS_RUNBOOK.md)
- [`docs/BACKEND_A.md`](docs/BACKEND_A.md)
- [`docs/BACKEND_B_COMMERCE.md`](docs/BACKEND_B_COMMERCE.md)
- [`docs/DATABASE.md`](docs/DATABASE.md)
- [`docs/INFRASTRUCTURE.md`](docs/INFRASTRUCTURE.md)

## 11) Limites atuais de documentação (sem inventar)
- Pipeline exato de deploy de frontend para provedor cloud específico: não está explicitamente versionado neste repositório.
- Estratégia completa de rollback de migrations em produção: não está explicitamente codificada em script único.

Nesses casos, o doc mantém marcação de “Não determinado a partir do código” para evitar inferência incorreta.
