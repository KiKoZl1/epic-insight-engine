# Setup Guide

This setup is for the current local-first workflow (frontend local + Supabase cloud backend owned by the project).

## Prerequisites

- Node.js 20+ (22 recommended)
- npm 9+
- Git
- Supabase CLI (`npx supabase@latest` or global install)
- Optional: `psql` if you want direct SQL from terminal

## 1) Install dependencies

```bash
npm install
```

## 2) Configure environment

Create `.env` in project root (do not commit it):

```env
VITE_SUPABASE_URL="https://<project-ref>.supabase.co"
VITE_SUPABASE_PUBLISHABLE_KEY="<anon-or-publishable-key>"
SUPABASE_URL="https://<project-ref>.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"

# Preferred LLM provider for current Ralph memory stack
NVIDIA_API_KEY="<nvidia-api-key>"

# Optional fallback provider
OPENAI_API_KEY="<openai-api-key>"
OPENAI_MODEL="gpt-4.1-mini"
OPENAI_TRANSLATION_MODEL="gpt-4.1-mini"
```

Reference template: `.env.example`.

## 3) Link Supabase project

```bash
npx supabase@latest login
npx supabase@latest link --project-ref <project-ref>
```

If link fails due to `config.toml` encoding, save `supabase/config.toml` as UTF-8 and retry.

## 4) Apply schema and deploy functions

```bash
npx supabase@latest db push
npx supabase@latest functions deploy
```

If you prefer selective deploy:

```bash
npx supabase@latest functions deploy discover-collector
```

## 5) Run frontend

```bash
npm run dev
```

Open `http://localhost:8080`.

## 6) Smoke checks

1. Login at `/auth` (email or Google).
2. Open `/app` and `/app/island-lookup`.
3. Open `/admin` as admin/editor user.
4. Verify command center loads without auth/RPC errors.

## Useful commands

```bash
npm run lint
npm run build
npm run test
npm run ralph:local
npm run ralph:loop
```

## Common issues

### Missing env values

- Reload terminal after editing `.env`.
- Confirm keys are in process env before running scripts.

### Edge Function 401/403

- Check `SUPABASE_SERVICE_ROLE_KEY`.
- Validate function auth mode (service role only vs admin/editor mode).

### Cron jobs failing with config errors

- Ensure cron commands use explicit project URL/service token strategy compatible with your project configuration.
- Use admin cron RPCs in this repo to pause/resume/list runs.
