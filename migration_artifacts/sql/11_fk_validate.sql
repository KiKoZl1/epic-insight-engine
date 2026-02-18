-- Run after bulk import window.
-- Restores FK checks and validates likely owner references.

set session_replication_role = origin;
commit;

-- Generic orphan checks (adjust/add tables as needed)
-- user_roles.user_id -> auth.users.id
select count(*) as orphan_user_roles
from public.user_roles ur
left join auth.users au on au.id = ur.user_id
where au.id is null;

-- weekly_reports.discover_report_id -> discover_reports.id
select count(*) as orphan_weekly_reports
from public.weekly_reports wr
left join public.discover_reports dr on dr.id = wr.discover_report_id
where wr.discover_report_id is not null
  and dr.id is null;

-- discover_report_islands.report_id -> discover_reports.id
select count(*) as orphan_report_islands
from public.discover_report_islands dri
left join public.discover_reports dr on dr.id = dri.report_id
where dr.id is null;

