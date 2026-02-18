-- Legacy overlap migration.
-- Intentionally no-op for fresh bootstrap because final function versions
-- are defined by later migrations in this repository.
DO $$
BEGIN
  RAISE NOTICE 'Skipping legacy migration 20260215202930 (no-op)';
END $$;
