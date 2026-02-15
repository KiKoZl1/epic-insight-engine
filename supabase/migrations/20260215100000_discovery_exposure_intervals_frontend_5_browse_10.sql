-- Final cadence policy:
-- - Frontend: every 5 minutes (captures premium panels and fast booms)
-- - Browse: every 10 minutes (heavier, less time-critical)

UPDATE public.discovery_exposure_targets
SET interval_minutes = 5
WHERE surface_name = 'CreativeDiscoverySurface_Frontend';

UPDATE public.discovery_exposure_targets
SET interval_minutes = 10
WHERE surface_name = 'CreativeDiscoverySurface_Browse';

