# Backend B - Commerce Edge API

Comprehensive technical reference for the `commerce` edge function.

This backend is the payment, credits, anti-abuse, and financial admin gateway.

## 1. Scope

Commerce is implemented as a single edge function with internal route dispatch.

Evidence:
- Single handler with path suffix router. (source: supabase/functions/commerce/index.ts:1558)
- Function registration in Supabase config. (source: supabase/config.toml:126)

## 2. Architecture

### 2.1 Request Flow

1. Parse route suffix from `/functions/v1/commerce/*`.
2. Resolve user from bearer token if present.
3. Dispatch to route-specific handler.
4. Apply auth and rate limit per route.
5. Return JSON envelope with explicit error mapping.

Evidence:
- Route parser helper and switch-like branch chain. (source: supabase/functions/commerce/index.ts:178, supabase/functions/commerce/index.ts:1563)
- Global error mapping to 401/403/500. (source: supabase/functions/commerce/index.ts:1719)

### 2.2 Security Layers

Commerce uses layered security:
- Config: `verify_jwt = false` (gateway does not auto-enforce JWT).
- Handler: explicit bearer resolution and user role checks.
- Admin routes: `requireFinancialAdmin`.
- Internal job routes: `x-commerce-internal-secret` OR admin.
- Webhook route: Stripe signature verification.

Evidence:
- Config flag. (source: supabase/config.toml:126)
- User resolution. (source: supabase/functions/commerce/index.ts:251)
- Admin guard. (source: supabase/functions/commerce/index.ts:280)
- Internal/admin guard. (source: supabase/functions/commerce/index.ts:284)
- Webhook signature parsing/tolerance in shared helper. (source: supabase/functions/_shared/stripeSignature.ts:6)

### 2.3 Rate Limiting

Rate limiting uses `commerce_check_rate_limit` RPC and route-specific scopes.

Evidence:
- Limiter implementation. (source: supabase/functions/commerce/index.ts:912)
- Execute scope and env-controlled threshold. (source: supabase/functions/commerce/index.ts:1589)
- Webhook scope. (source: supabase/functions/commerce/index.ts:1649)

## 3. External Dependencies and Integrations

- Supabase auth and Postgres RPC.
- Stripe checkout sessions and webhook events.
- Tool dispatch into TGIS functions via signed gateway headers.

Evidence:
- Stripe checkout API call. (source: supabase/functions/commerce/index.ts:398)
- Tool dispatch function invocation and signature header. (source: supabase/functions/commerce/index.ts:293)
- RPC usage across account and credits lifecycle. (source: supabase/functions/commerce/index.ts:603)

## 4. Database Side Effects (RPC + Table Mutations)

### 4.1 RPC calls used by commerce

- `commerce_ensure_account`
- `commerce_open_cycle_if_needed`
- `commerce_sync_access_state`
- `commerce_debit_tool_credits`
- `commerce_mark_usage_attempt_result`
- `commerce_reverse_operation`
- `commerce_check_rate_limit`
- `commerce_grant_pack_credits`
- `commerce_admin_adjust_credits`
- `commerce_admin_lookup_user_by_email`
- `commerce_weekly_release_job`
- `commerce_reconcile_job`

Evidence:
- RPC invocations in handler code. (source: supabase/functions/commerce/index.ts:603)

### 4.2 Direct table reads/writes

Reads and writes happen in:
- `commerce_accounts`
- `commerce_wallets`
- `commerce_subscriptions`
- `commerce_ledger`
- `commerce_tool_usage_attempts`
- `commerce_abuse_signals`
- `commerce_webhook_events`
- `commerce_config`
- `user_roles`
- `profiles`

Evidence:
- Account/wallet/subscription reads in credits flow. (source: supabase/functions/commerce/index.ts:607)
- Webhook event persistence. (source: supabase/functions/commerce/index.ts:1336)

## 5. API Contracts

Base path: `/functions/v1/commerce`

For each endpoint below, schema is extracted from runtime validation in code.

## 5.1 Catalog and User Credits

### GET `/catalog/tool-costs`

- Handler: `handleCatalogToolCosts`.
- Auth: none.
- Query params: none.
- Response 200: `{ success: true, tool_costs: Record<string, number> }`.
- Error responses: 500 on DB/config read failure.
- Side effects: none (read-only).

Evidence:
- Route mapping. (source: supabase/functions/commerce/index.ts:1563)
- Handler implementation. (source: supabase/functions/commerce/index.ts:895)

### GET `/me/credits`

- Handler: `handleMeCredits`.
- Auth: bearer user required.
- Query params: none.
- Response 200: account/wallet/cycle/subscription/summary bundle.
- Error responses:
  - 401 unauthorized
  - 500 internal error
- Side effects:
  - ensure account
  - open billing cycle if needed
  - sync access state

Evidence:
- Route mapping and auth check. (source: supabase/functions/commerce/index.ts:1567)
- Side-effect RPC calls. (source: supabase/functions/commerce/index.ts:603)

### GET `/me/credits/summary`

- Handler: `handleMeCreditsSummary`.
- Auth: bearer user required.
- Query params: none.
- Response 200: compact account/wallet/summary object.
- Error responses: 401/500.
- Side effects: account ensure + optional cycle open.

Evidence:
- Route mapping. (source: supabase/functions/commerce/index.ts:1572)
- Handler behavior. (source: supabase/functions/commerce/index.ts:634)

### GET `/me/ledger`

- Handler: `handleMeLedger`.
- Auth: bearer user required.
- Query params:
  - `limit` (int, optional, default 50, range 1..200)
  - `before_id` (int, optional)
- Response 200: `{ success: true, items: [...] }`.
- Error responses: 401/500.
- Side effects: none (read-only).

Evidence:
- Query parsing and limits. (source: supabase/functions/commerce/index.ts:670)

### GET `/me/usage-summary`

- Handler: `handleMeUsageSummary`.
- Auth: bearer user required.
- Query params: none.
- Response 200: `{ success, cycle_id, total_credits_used, by_tool }`.
- Error responses: 401/500.
- Side effects: none (read-only aggregation).

Evidence:
- Usage summary aggregation. (source: supabase/functions/commerce/index.ts:689)

## 5.2 Tool Consumption

### POST `/tools/execute`

- Handler: `handleToolsExecute`.
- Auth: bearer user required.
- Middleware: rate limit scope `tools_execute`.
- Body schema:
  - `tool_code` (required, enum in code)
  - `payload` (object, optional)
  - `request_id` (optional, auto-generated)
  - `idempotency_key` (required in header or body)
- Response 200:
  - success envelope with `operation_id`
  - remaining wallet counters
  - optional `tool_result` (for dispatched tools)
- Error responses:
  - 400 missing/invalid fields
  - 402 insufficient credits / blocked state
  - 401 unauthorized
  - 422/4xx/5xx from downstream dispatch
  - 429 rate limit
- Side effects:
  - debit credits RPC
  - usage attempt status logging
  - optional auto-reversal when dispatch fails under selected conditions
  - optional tool dispatch call

Evidence:
- Route and limiter. (source: supabase/functions/commerce/index.ts:1587)
- Field validations. (source: supabase/functions/commerce/index.ts:724)
- Debit RPC. (source: supabase/functions/commerce/index.ts:735)
- Auto-reversal condition and action. (source: supabase/functions/commerce/index.ts:818)

### POST `/tools/reverse`

- Handler: `handleToolsReverse`.
- Auth: bearer user required.
- Middleware: rate limit scope `tools_reverse`.
- Body schema:
  - `operation_id` (required)
  - `reason` (optional, default `manual_reversal`)
  - `idempotency_key` (required)
- Response 200: `{ success: true, reversal }`.
- Error responses: 400/401/429/500.
- Side effects: credit reversal via RPC.

Evidence:
- Route and limiter. (source: supabase/functions/commerce/index.ts:1601)
- Validation and reversal RPC. (source: supabase/functions/commerce/index.ts:866)

## 5.3 Subscription and Pack Checkout

### POST `/billing/subscription/checkout`

- Handler: `handleBillingSubscriptionCheckout`.
- Auth: bearer user required.
- Middleware: rate limit scope `billing_subscription_checkout`.
- Body schema:
  - `plan_code` (optional, only `pro` supported)
  - `success_url` (optional)
  - `cancel_url` (optional)
  - `idempotency_key` (required)
- Response 200: checkout URL + session id.
- Error responses:
  - 400 invalid input
  - 503 Stripe price not configured
  - 401/429/500
- Side effects:
  - ensure account
  - create Stripe checkout session

Evidence:
- Route mapping. (source: supabase/functions/commerce/index.ts:1615)
- Handler validation and Stripe creation. (source: supabase/functions/commerce/index.ts:1078)

### GET `/billing/packs`

- Handler: `handleBillingPacksList`.
- Auth: bearer user required.
- Response 200: `{ success, enabled, packs[] }`.
- Error responses: 401/500.
- Side effects: none.

Evidence:
- Route mapping. (source: supabase/functions/commerce/index.ts:1629)
- Config read logic. (source: supabase/functions/commerce/index.ts:882)

### POST `/billing/packs/{packCode}/checkout`

- Handler: `handleBillingPackCheckout`.
- Auth: bearer user required.
- Middleware: rate limit scope `billing_pack_checkout`.
- Path params:
  - `packCode` (required)
- Body schema:
  - `success_url` (optional)
  - `cancel_url` (optional)
  - `idempotency_key` (required)
- Response 200: checkout URL + session info.
- Error responses: 400/401/404/429/500.
- Side effects: ensure account + Stripe session creation.

Evidence:
- Route mapping and packCode extraction. (source: supabase/functions/commerce/index.ts:1634)
- Handler validation for pack checkout. (source: supabase/functions/commerce/index.ts:1117)

### POST `/billing/webhooks/provider`

- Handler: `handleWebhook`.
- Auth: Stripe signature header, no bearer required.
- Middleware: rate limit scope `billing_webhook_provider`.
- Headers required:
  - `stripe-signature`
- Body: raw Stripe event payload.
- Response 200: processed marker.
- Error responses:
  - 400 invalid signature/body
  - 429 rate limit
  - 500 process failure
- Side effects:
  - persist event status in `commerce_webhook_events`
  - update subscription and ledger state depending on event type

Evidence:
- Route mapping. (source: supabase/functions/commerce/index.ts:1649)
- Handler and event status updates. (source: supabase/functions/commerce/index.ts:1177)
- Signature helpers. (source: supabase/functions/_shared/stripeSignature.ts:6)

## 5.4 Admin APIs

All admin APIs require bearer user + `requireFinancialAdmin`.

Evidence:
- Admin guard call sites. (source: supabase/functions/commerce/index.ts:1662)

### GET `/admin/user-lookup?email=...`

- Handler: `handleAdminUserLookup`.
- Query params:
  - `email` (required)
- Response 200: user identity snapshot and role.
- Error responses: 400 invalid email, 404 not found, 401/403/500.

Evidence:
- Query validation. (source: supabase/functions/commerce/index.ts:1442)

### GET `/admin/user/{userId}`

- Handler: `handleAdminUserOverview`.
- Path params: `userId` required.
- Response 200: deep user financial dossier (account/wallet/subscription/ledger/attempts/abuse).
- Error responses: 404 user not found, 401/403/500.

Evidence:
- Overview query fan-out and response payload. (source: supabase/functions/commerce/index.ts:1345)

### POST `/admin/credits/grant`
### POST `/admin/credits/debit`

- Handler: `handleAdminCreditAdjust`.
- Body schema:
  - `user_id` (required)
  - `wallet_type` (optional, default `extra_wallet`)
  - `credits` or `amount` (required > 0)
  - `reason` (required)
  - `idempotency_key` (required)
  - `reference_id` (optional)
- Response 200: RPC result envelope.
- Error responses: 400 validation errors, 401/403/500.
- Side effects: ledger + wallet mutation through `commerce_admin_adjust_credits`.

Evidence:
- Validation and RPC args. (source: supabase/functions/commerce/index.ts:1468)

### POST `/admin/user/{userId}/abuse-review`

- Handler: `handleAdminAbuseReview`.
- Body schema:
  - `action` (`approve|review|block`, optional defaults)
  - `reason` (optional)
  - `idempotency_key` (required)
- Response 200: `{ success: true, action }`.
- Error responses: 400/401/403/500.
- Side effects:
  - update account anti-abuse flags
  - insert abuse signal
  - optionally sync access state

Evidence:
- Action patch behavior and insert side effects. (source: supabase/functions/commerce/index.ts:1498)

### POST `/admin/user/{userId}/suspend`

- Handler: `handleAdminSuspend`.
- Body schema:
  - `suspend` (boolean, optional default true)
- Response 200: `{ success: true, account }`.
- Error responses: 401/403/500.
- Side effects:
  - account `access_state` change or sync restore.

Evidence:
- Suspension logic. (source: supabase/functions/commerce/index.ts:1539)

## 5.5 Internal Job APIs

### POST `/internal/jobs/weekly-release`
### POST `/internal/jobs/reconcile`

- Auth: `x-commerce-internal-secret` OR admin user.
- Response 200: job result.
- Error responses: 403/500.

Evidence:
- Internal route guards and RPC calls. (source: supabase/functions/commerce/index.ts:1701)

## 6. Frontend Integration Map

Frontend calls Commerce directly via `fetch` to `/functions/v1/commerce*` from `src/lib/commerce/client.ts`.

Key client behavior:
- Reads Supabase session and sends bearer token.
- Adds idempotency and device fingerprint headers.
- Performs optimistic UI debit + rollback events around tool execution.
- Caches selected GET responses with TTL.

Evidence:
- Commerce client request builder. (source: src/lib/commerce/client.ts:68)
- Device fingerprint + idempotency headers. (source: src/lib/commerce/client.ts:55)
- Optimistic debit flow. (source: src/lib/commerce/client.ts:176)

## 7. Error Model and Status Codes

Observed canonical errors include:
- `unauthorized` -> 401
- `forbidden` -> 403
- validation errors -> 400
- insufficient credits branch -> 402
- rate limit -> 429
- internal errors -> 500

Evidence:
- Global catch status mapping. (source: supabase/functions/commerce/index.ts:1719)
- Insufficient credits response branch. (source: supabase/functions/commerce/index.ts:746)
- Rate limiter response path. (source: supabase/functions/commerce/index.ts:912)

## 8. x-doc-status and Confidence

`x-doc-status: complete` for route-level contracts and validation-gated body fields.

`x-doc-status: incomplete` for exact Stripe provider payload schema and some nested `metadata_json` object shapes that are pass-through.

Reason:
- Handler validates only selected fields and forwards nested objects dynamically.

Evidence:
- Dynamic webhook payload use. (source: supabase/functions/commerce/index.ts:1177)

## 9. OpenAPI

Commerce OpenAPI file:
- `docs/openapi-backend-b-commerce.yaml`

The spec aligns with route map and auth schemes, with field-level detail varying by endpoint.

Evidence:
- Spec root and path list. (source: docs/openapi-backend-b-commerce.yaml:1)
