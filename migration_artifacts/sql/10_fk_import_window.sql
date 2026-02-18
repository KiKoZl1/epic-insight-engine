-- Use only during bulk CSV import if FK constraints block progress.
-- Requires high-privilege role in SQL editor.
-- IMPORTANT: Run 11_fk_validate.sql right after imports.

begin;

-- Session-level bypass for FK checks during import.
set local session_replication_role = replica;

-- Keep this transaction open only while importing.
-- After imports, run:
--   set local session_replication_role = origin;
--   commit;

