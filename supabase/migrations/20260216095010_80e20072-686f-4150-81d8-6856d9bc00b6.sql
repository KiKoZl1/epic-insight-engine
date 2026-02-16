
-- Drop the duplicate text-parameter versions that cause ambiguity
DROP FUNCTION IF EXISTS public.report_finalize_exposure_analysis(text, integer);
DROP FUNCTION IF EXISTS public.report_finalize_exposure_efficiency(text, integer);
