-- Legacy overlap migration.
-- Intentionally no-op because Ralph ops foundation is already defined
-- in migration 20260216123000_ralph_ops_foundation.sql.
DO $$
BEGIN
  RAISE NOTICE 'Skipping legacy migration 20260216154827 (no-op)';
END $$;
