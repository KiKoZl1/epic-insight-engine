-- Run in OLD and NEW projects, export results and compare.

-- Exact row counts for core tables
select 'discover_islands_cache' as table_name, count(*)::bigint as row_count from public.discover_islands_cache
union all
select 'discover_link_metadata', count(*)::bigint from public.discover_link_metadata
union all
select 'discover_reports', count(*)::bigint from public.discover_reports
union all
select 'discover_report_islands', count(*)::bigint from public.discover_report_islands
union all
select 'weekly_reports', count(*)::bigint from public.weekly_reports
union all
select 'discovery_exposure_rollup_daily', count(*)::bigint from public.discovery_exposure_rollup_daily
union all
select 'user_roles', count(*)::bigint from public.user_roles
order by table_name;

-- Auth totals
select count(*)::bigint as auth_users from auth.users;

-- Storage totals
select bucket_id, count(*)::bigint as object_count
from storage.objects
group by bucket_id
order by bucket_id;

