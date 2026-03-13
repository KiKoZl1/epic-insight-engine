# Infrastructure and Configuration

Infrastructure reference derived from code and deployment artifacts in repository.

## 1. Infrastructure Inventory

## 1.1 Frontend Runtime

- Vite dev server listens on host `::` and port `8080`.
- Build is static (`vite build`) with sourcemaps disabled.

Evidence:
- Vite server and build config. (source: vite.config.ts:7)
- NPM scripts. (source: package.json:7)

## 1.2 Backend Runtime

- Supabase Edge Functions under `supabase/functions/*`.
- Per-function `verify_jwt` policy configured in `supabase/config.toml`.

Evidence:
- Function config declarations. (source: supabase/config.toml:3)

## 1.3 Data Layer

- Postgres schema is managed by SQL migrations in `supabase/migrations`.
- Remote SQL tooling depends on `SUPABASE_DB_URL` and local `psql`.

Evidence:
- SQL runner env and behavior. (source: scripts/sql.ps1:58)
- Example DB URL format. (source: .env.example:12)

## 1.4 ML Worker Runtime

Two worker families are present:
- DPPI worker (timer-driven)
- TGIS worker (timer-driven + local supervisor scripts)

Evidence:
- DPPI systemd units. (source: ml/dppi/deploy/systemd/dppi-worker.service:1)
- TGIS systemd units. (source: ml/tgis/deploy/systemd/tgis-worker.service:1)

## 1.5 Operator Scripts

Repository includes scripts for:
- environment target switching
- SQL execution
- Ralph local automation loop
- TGIS bootstrap

Evidence:
- Script inventory. (source: package.json:18)
- Target-switch implementation. (source: scripts/migration-set-target.ps1:1)

## 2. Service Topology

## 2.1 Primary Service Graph

1. Browser frontend -> Supabase Edge Functions.
2. Frontend -> Postgres through `discover-data-api` abstraction.
3. Commerce edge function -> TGIS edge functions for tool dispatch.
4. Discover edge handlers -> optional Data Supabase project via bridge.
5. ML workers -> Supabase DB and edge callback endpoints.

Evidence:
- Frontend data API invocation. (source: src/lib/discoverDataApi.ts:60)
- Commerce tool dispatch to edge functions. (source: supabase/functions/commerce/index.ts:323)
- Data bridge to external Supabase function URL. (source: supabase/functions/_shared/dataBridge.ts:109)
- TGIS webhook endpoint registered. (source: supabase/config.toml:108)

## 2.2 Port and Endpoint Notes

- Frontend local dev port: `8080`.
- Edge function routes: `/functions/v1/<function-name>`.
- No in-repo Kubernetes or Docker Compose manifests defining additional app ports.

Evidence:
- Vite config port. (source: vite.config.ts:9)
- Edge route naming from config and client builders. (source: supabase/config.toml:3, src/lib/commerce/client.ts:92)

## 3. Environment Variables

The tables below document required/optional variables found in tracked config examples and scripts.

## 3.1 Core Frontend and Supabase App

| Variable | Purpose | Required | Default | Source |
|---|---|---|---|---|
| `VITE_SUPABASE_URL` | Frontend Supabase base URL | yes | none | `.env.example` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Frontend anon/publishable key | yes | none | `.env.example` |
| `VITE_BRAND_NAME` | UI brand string | optional | `UEFNToolkit` example | `.env.example` |
| `VITE_CANONICAL_URL` | canonical website URL | optional | example value | `.env.example` |
| `SUPABASE_URL` | edge/runtime Supabase URL | yes | none | `.env.example` |
| `SUPABASE_SERVICE_ROLE_KEY` | privileged service key | yes for server scripts/functions | none | `.env.example` |
| `SUPABASE_DB_URL` | Postgres connection URL for SQL runner | required for SQL scripts | none | `.env.example` |

Evidence:
- Variable declarations. (source: .env.example:1)

## 3.2 Data Bridge Variables

| Variable | Purpose | Required for bridge | Default | Source |
|---|---|---|---|---|
| `DATA_SUPABASE_URL` | target data project URL | yes | none | `.env.example` |
| `DATA_SUPABASE_SERVICE_ROLE_KEY` | data project service key | yes | none | `.env.example` |
| `INTERNAL_BRIDGE_SECRET` | shared bridge auth secret | yes | none | `.env.example` |
| `LOOKUP_DATA_TIMEOUT_MS` | proxy timeout tuning | optional | 4500 example | `.env.example` |
| `DISCOVERY_DPPI_PROXY_STRICT` | fail-closed proxy behavior | optional | `true` example | `.env.example` |

Evidence:
- Env examples for bridge. (source: .env.example:13)
- Strict proxy implementation reads this flag. (source: supabase/functions/_shared/dataBridge.ts:68)

## 3.3 AI/LLM API Keys in App Env

| Variable | Purpose | Required | Default | Source |
|---|---|---|---|---|
| `OPENAI_API_KEY` | OpenAI access for edge workflows | conditional | none | `.env.example` |
| `OPENAI_MODEL` | default OpenAI model | optional | `gpt-4.1-mini` example | `.env.example` |
| `OPENAI_TRANSLATION_MODEL` | translation model override | optional | `gpt-4.1-mini` example | `.env.example` |
| `NVIDIA_API_KEY` | NVIDIA API access | conditional | none | `.env.example` |
| `NVIDIA_LOOKUP_MODEL` | lookup model identifier | optional | example value | `.env.example` |

Evidence:
- AI variable declarations. (source: .env.example:20)

## 3.4 Commerce/Stripe Variables

| Variable | Purpose | Required | Default | Source |
|---|---|---|---|---|
| `APP_BASE_URL` | checkout URL base | yes in checkout flows | none | `.env.example` |
| `STRIPE_SECRET_KEY` | Stripe API secret | yes for checkout/webhook processing | none | `.env.example` |
| `STRIPE_WEBHOOK_SECRET` | webhook signature verification | yes for webhook route | none | `.env.example` |
| `STRIPE_PRICE_PRO_MONTHLY` | subscription price ID | yes for subscription checkout | none | `.env.example` |
| `STRIPE_PRICE_PACK_250` | pack small price ID | yes for pack checkout | none | `.env.example` |
| `STRIPE_PRICE_PACK_650` | pack medium price ID | yes for pack checkout | none | `.env.example` |
| `STRIPE_PRICE_PACK_1400` | pack large price ID | yes for pack checkout | none | `.env.example` |
| `COMMERCE_GATEWAY_SECRET` | signed dispatch from commerce to tools | recommended | none | `.env.example` |
| `COMMERCE_GATEWAY_ENFORCE` | enforce signature behavior | optional | `true` example | `.env.example` |
| `COMMERCE_INTERNAL_SECRET` | internal jobs auth header secret | recommended | none | `.env.example` |
| `COMMERCE_RATE_LIMIT_*` | route-specific rate thresholds | optional | code/env defaults | `.env.example` |

Evidence:
- Commerce env block. (source: .env.example:27)
- Rate limit env reads in handler. (source: supabase/functions/commerce/index.ts:1594)

## 3.5 DPPI Worker Env

| Variable | Purpose | Required | Source |
|---|---|---|---|
| `SUPABASE_URL` | worker Supabase target | yes | `ml/dppi/deploy/worker.env.example` |
| `SUPABASE_SERVICE_ROLE_KEY` | worker service credentials | yes | `ml/dppi/deploy/worker.env.example` |
| `SUPABASE_DB_URL` | direct DB access | yes | `ml/dppi/deploy/worker.env.example` |
| `DPPI_WORKER_HOST` | heartbeat host id | optional/recommended | `ml/dppi/deploy/worker.env.example` |
| `DPPI_WORKER_SOURCE` | host source tag | optional/recommended | `ml/dppi/deploy/worker.env.example` |
| `DPPI_CONFIG_PATH` | config file path | optional/recommended | `ml/dppi/deploy/worker.env.example` |

Evidence:
- DPPI worker env example. (source: ml/dppi/deploy/worker.env.example:1)

## 3.6 TGIS Worker Env

| Variable | Purpose | Required | Source |
|---|---|---|---|
| `SUPABASE_URL` | worker Supabase target | yes | `ml/tgis/deploy/worker.env.example` |
| `SUPABASE_SERVICE_ROLE_KEY` | worker service credentials | yes | `ml/tgis/deploy/worker.env.example` |
| `SUPABASE_DB_URL` | direct DB/pooler URL | yes | `ml/tgis/deploy/worker.env.example` |
| `OPENROUTER_API_KEY` | LLM rewrite/generation integration | conditional | `ml/tgis/deploy/worker.env.example` |
| `FAL_API_KEY` / `FAL_KEY` | FAL provider auth | yes for TGIS generation/training | `ml/tgis/deploy/worker.env.example` |
| `RUNPOD_API_KEY` | RunPod training orchestration | conditional | `ml/tgis/deploy/worker.env.example` |
| `AI_TOOLKIT_RUNNER` | AI Toolkit runner path | conditional | `ml/tgis/deploy/worker.env.example` |
| `AI_TOOLKIT_PYTHON` | AI Toolkit python path | conditional | `ml/tgis/deploy/worker.env.example` |
| `TGIS_WORKER_HOST` | heartbeat host id | recommended | `ml/tgis/deploy/worker.env.example` |
| `TGIS_WORKER_SOURCE` | host source tag | recommended | `ml/tgis/deploy/worker.env.example` |
| `TGIS_CONFIG_PATH` | runtime config path | recommended | `ml/tgis/deploy/worker.env.example` |
| `TGIS_WEBHOOK_URL` | training callback URL | yes for training callbacks | `ml/tgis/deploy/worker.env.example` |
| `TGIS_WEBHOOK_SECRET` | webhook token secret | yes for webhook auth | `ml/tgis/deploy/worker.env.example` |
| `TGIS_FAL_TRAINER_MODEL` | trainer model id | optional override | `ml/tgis/deploy/worker.env.example` |

Evidence:
- TGIS worker env example. (source: ml/tgis/deploy/worker.env.example:1)

## 4. Scheduling and Worker Orchestration

## 4.1 DPPI Scheduler

- `dppi-worker.timer` runs every 10 minutes.
- service executes `python ml/dppi/pipelines/worker_tick.py`.

Evidence:
- Timer interval. (source: ml/dppi/deploy/systemd/dppi-worker.timer:5)
- Service exec command. (source: ml/dppi/deploy/systemd/dppi-worker.service:12)

## 4.2 TGIS Scheduler

- `tgis-worker.timer` runs every 1 minute.
- service executes `python -m ml.tgis.runtime.worker_tick`.

Evidence:
- Timer interval. (source: ml/tgis/deploy/systemd/tgis-worker.timer:5)
- Service exec command. (source: ml/tgis/deploy/systemd/tgis-worker.service:10)

## 4.3 Local TGIS Worker Supervision

Local operator scripts:
- start local supervisor process
- ensure process is running from PID file
- status script with stdout/stderr tail

Evidence:
- Start script process management. (source: ml/tgis/deploy/start_local_worker.ps1:47)
- Ensure script auto-start logic. (source: ml/tgis/deploy/ensure_local_worker.ps1:23)
- Status script diagnostics output. (source: ml/tgis/deploy/status_local_worker.ps1:26)

## 5. Configuration Mutation Tooling

## 5.1 `migration-set-target`

Script updates `.env` and `supabase/config.toml` for a new Supabase project target.

Behavior:
- backs up files to `migration_artifacts/logs`
- upserts `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_URL`
- rewrites `project_id` in config

Evidence:
- Backup and upsert code. (source: scripts/migration-set-target.ps1:45)
- Config project rewrite. (source: scripts/migration-set-target.ps1:79)

## 5.2 SQL Runner

`scripts/sql.ps1` supports:
- inline query mode (`-Query`)
- file mode (`-File`)
- strict `ON_ERROR_STOP`

Prereqs:
- `SUPABASE_DB_URL` present
- `psql` installed locally

Evidence:
- Input validation and command assembly. (source: scripts/sql.ps1:68)

## 6. Security-Critical Configuration Points

- Service keys are used in edge and worker contexts; leakage risk is high.
- `INTERNAL_BRIDGE_SECRET` gates cross-project forwarding.
- `COMMERCE_INTERNAL_SECRET` gates internal job endpoints.
- Stripe secrets gate financial webhook integrity.

Evidence:
- Bridge secret enforcement. (source: supabase/functions/_shared/dataBridge.ts:31)
- Internal secret check in commerce. (source: supabase/functions/commerce/index.ts:285)
- Stripe secret env read in checkout path. (source: supabase/functions/commerce/index.ts:383)

## 7. Not Determined From Code

The following cannot be determined with certainty from repository source alone:
- cloud provider load balancer/network ACL setup
- CDN layer and edge cache provider configuration
- production secret storage mechanism (vault/manager)
- formal Kubernetes/Terraform topology (files not present)

Status: Not determined from code.

## 8. Maintenance Guidance

When changing infrastructure behavior in this repo, update:
1. `supabase/config.toml` for function exposure/auth flags.
2. `.env.example` and worker env examples for new required variables.
3. systemd units under `ml/*/deploy/systemd` for worker schedule changes.
4. docs in `INFRASTRUCTURE.md`, `DEPLOYMENT_RUNBOOK.md`, and `OPERATIONS_RUNBOOK.md`.

Evidence:
- Function registry source of truth. (source: supabase/config.toml:3)
- Worker schedule source of truth. (source: ml/tgis/deploy/systemd/tgis-worker.timer:1)
