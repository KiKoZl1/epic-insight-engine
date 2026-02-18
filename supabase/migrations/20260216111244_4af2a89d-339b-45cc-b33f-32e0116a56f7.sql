-- Legacy overlap migration.
-- Intentionally no-op for fresh bootstrap because lookup pipeline
-- objects are already defined by surrounding migrations.
DO $$
BEGIN
  RAISE NOTICE 'Skipping legacy migration 20260216111244 (no-op)';
END $$;
