-- Exposure apply can legitimately process large batches and may exceed the default statement timeout.
-- Increase timeout only for this function to reduce false pipeline failures.
ALTER FUNCTION public.apply_discovery_exposure_tick(
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  jsonb,
  integer,
  text
)
SET statement_timeout = '120s';
