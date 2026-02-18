-- Legacy overlap migration.
-- Intentionally no-op for fresh bootstrap because equivalent/final objects
-- are created by surrounding migrations in this repository.
DO $$
BEGIN
  RAISE NOTICE 'Skipping legacy migration 20260215202416 (no-op)';
END $$;
