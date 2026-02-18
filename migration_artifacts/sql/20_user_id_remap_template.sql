-- 1) Create temp map table and load old/new user IDs.
create temp table if not exists tmp_user_id_map (
  old_user_id uuid primary key,
  new_user_id uuid not null
);

-- 2) Insert mappings (example).
-- insert into tmp_user_id_map (old_user_id, new_user_id) values
-- ('00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

-- 3) Apply remap in tables that store user_id.
update public.user_roles ur
set user_id = m.new_user_id
from tmp_user_id_map m
where ur.user_id = m.old_user_id;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ralph_runs'
      and column_name = 'created_by'
  ) then
    update public.ralph_runs rr
    set created_by = m.new_user_id
    from tmp_user_id_map m
    where rr.created_by = m.old_user_id;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'discover_report_rebuild_runs'
      and column_name = 'user_id'
  ) then
    update public.discover_report_rebuild_runs r
    set user_id = m.new_user_id
    from tmp_user_id_map m
    where r.user_id = m.old_user_id;
  end if;
end $$;

-- 4) Validate no unmapped IDs remain.
select count(*) as user_roles_orphans
from public.user_roles ur
left join auth.users au on au.id = ur.user_id
where au.id is null;
