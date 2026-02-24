CREATE OR REPLACE FUNCTION public.report_link_metadata_coverage(p_report_id UUID)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '120s'
AS $$
  SELECT jsonb_build_object(
    'reported_islands', (SELECT COUNT(*) FROM public.discover_report_islands WHERE report_id = p_report_id AND status = 'reported'),
    'with_title', (
      SELECT COUNT(*)
      FROM public.discover_report_islands ri
      JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
      WHERE ri.report_id = p_report_id AND ri.status = 'reported'
        AND m.title IS NOT NULL AND m.title <> ''
    ),
    'with_image_url', (
      SELECT COUNT(*)
      FROM public.discover_report_islands ri
      JOIN public.discover_link_metadata m ON m.link_code = ri.island_code
      WHERE ri.report_id = p_report_id AND ri.status = 'reported'
        AND m.image_url IS NOT NULL AND m.image_url <> ''
    )
  );
$$;
