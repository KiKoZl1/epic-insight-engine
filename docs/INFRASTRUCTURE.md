# Infrastructure & Configuration

## 1. Inventário de infraestrutura versionada
### 1.1 Frontend runtime
- Vite dev server (`host ::`, `port 8080`). (fonte: `vite.config.ts:7`)
- Build estático via `vite build`. (fonte: `package.json:8`)

### 1.2 Backend runtime
- Supabase Edge Functions em `supabase/functions/*`.
- Controle de `verify_jwt` por função em `supabase/config.toml`.

(fonte: `supabase/config.toml:3`)

### 1.3 Banco
- Migrations SQL em `supabase/migrations/*`.
- SQL remoto via `SUPABASE_DB_URL` e psql runner.

(fonte: `.env.example:12`, `scripts/sql.ps1:58`)

### 1.4 Pipelines/Workers
- DPPI e TGIS com scripts de deploy/worker em `ml/*/deploy`.
- Setup TGIS com preflight/check de artefatos via `scripts/setup_tgis.sh`.

(fonte: `scripts/setup_tgis.sh:80`)

## 2. Variáveis de ambiente por domínio
## 2.1 Core app
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

(fonte: `.env.example:1`)

## 2.2 Brand/domain
- `VITE_BRAND_NAME`
- `VITE_CANONICAL_URL`
- `BRAND_NAME`
- `BRAND_CANONICAL_DOMAIN`

(fonte: `.env.example:3`)

## 2.3 Data bridge
- `DATA_SUPABASE_URL`
- `DATA_SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_BRIDGE_SECRET`
- `LOOKUP_DATA_TIMEOUT_MS`
- `DISCOVERY_DPPI_PROXY_STRICT`

(fonte: `.env.example:13`, `supabase/functions/_shared/dataBridge.ts:36`)

## 2.4 LLM providers
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `OPENAI_TRANSLATION_MODEL`
- `NVIDIA_API_KEY`
- `NVIDIA_LOOKUP_MODEL`

(fonte: `.env.example:20`)

## 2.5 Commerce/Stripe
- `APP_BASE_URL`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_PRO_MONTHLY`
- `STRIPE_PRICE_PACK_250`
- `STRIPE_PRICE_PACK_650`
- `STRIPE_PRICE_PACK_1400`
- `COMMERCE_GATEWAY_SECRET`
- `COMMERCE_INTERNAL_SECRET`
- `COMMERCE_RATE_LIMIT_*`

(fonte: `.env.example:29`)

## 3. Portas e endpoints
- Frontend local: `http://localhost:8080`. (fonte: `vite.config.ts:9`)
- Playwright webserver: `127.0.0.1:4173`. (fonte: `playwright.config.ts:16`)
- Supabase Functions: `https://<project-ref>.supabase.co/functions/v1/<function-name>`.
  - Exemplo deploy command no script de tuning. (fonte: `scripts/set-discover-metrics-profile.ps1:145`)

## 4. Topologia de comunicação
1. Browser -> Frontend React
2. Frontend -> Supabase Auth + PostgREST + Functions
3. Discover Functions -> (opcional) Data Supabase bridge
4. Commerce Function -> Stripe API
5. ML workers -> Supabase DB + artefatos locais/cloud

Evidência:
- Supabase client frontend. (fonte: `src/integrations/supabase/client.ts:11`)
- bridge forwarding. (fonte: `supabase/functions/_shared/dataBridge.ts:107`)
- Stripe requests backend. (fonte: `supabase/functions/commerce/index.ts:398`)

## 5. Segurança de configuração
- `verify_jwt` não é uniforme; revisar função por função. (fonte: `supabase/config.toml:7`)
- Commerce implementa auth explícita de usuário/admin/internal. (fonte: `supabase/functions/commerce/index.ts:280`)
- Fingerprint de dispositivo enviado no client commerce (`x-device-fingerprint-hash`). (fonte: `src/lib/commerce/client.ts:56`)

## 6. Automação/ops scripts relevantes
- `scripts/migration-set-target.ps1`: troca project target de forma segura com backup.
- `scripts/set-discover-metrics-profile.ps1`: aplica tuning de métricas via secrets set.
- `scripts/sql.ps1`: executor SQL remoto via psql.
- `scripts/export_supabase_tables.mjs`: export de tabelas para CSV.
- `scripts/setup_tgis.sh`: setup de worker TGIS e preflight.

(fonte: `scripts/migration-set-target.ps1:37`, `scripts/set-discover-metrics-profile.ps1:126`, `scripts/sql.ps1:55`, `scripts/export_supabase_tables.mjs:54`, `scripts/setup_tgis.sh:62`)

## 7. Infra não encontrada explicitamente
- Docker Compose / Kubernetes / Terraform como IaC principal.
- Pipeline CI/CD declarativo versionado em `.github/workflows`.

Status: **Não determinado a partir do código**.
