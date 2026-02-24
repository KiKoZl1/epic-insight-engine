# Contributing Guide

This repository follows a pragmatic, production-minded workflow.

## Branch policy

1. Keep `main` as release branch.
2. Never do feature work directly on `main`.
3. Use short-lived branches:
   - `feat/*`
   - `fix/*`
   - `ops/*`
   - `docs/*`

For Ralph autonomous loops, branch isolation is mandatory.

## Minimal quality gates

Before merge:

```bash
npm run lint
npm run build
npm run test
```

If a change is docs-only, call that out in commit/PR and skip irrelevant gates intentionally.

## Commit style

Use clear conventional prefixes:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `refactor: ...`
- `chore: ...`
- `ops: ...`

Keep commits atomic and easy to revert.

## Supabase change rules

1. Schema changes only via migration files in `supabase/migrations`.
2. Edge Function changes under `supabase/functions/<name>/index.ts`.
3. Deploy/test commands must be recorded in PR notes or handoff notes.
4. Never commit secrets (`.env`, keys, tokens, private JSON credentials).

## Documentation rules

1. `docs/` holds active source-of-truth guides.
2. Move obsolete material to `docs/archive/`.
3. Update `docs/README.md` when adding/removing major docs.

## Pull request checklist

1. Problem and scope are clear.
2. Change summary is explicit.
3. Risks and rollback are defined.
4. Validation evidence is included (screenshots/logs/queries where relevant).
5. Follow-up items are listed if anything is intentionally deferred.
