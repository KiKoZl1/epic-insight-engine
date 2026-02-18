-- Run in OLD project first, then NEW project for comparison snapshots.

-- Tables and row counts (public schema)
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.reltuples::bigint as estimated_rows
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname = 'public'
order by c.relname;

-- Functions inventory
select
  routine_schema,
  routine_name
from information_schema.routines
where routine_schema = 'public'
order by routine_name;

-- Cron jobs inventory (if pg_cron installed)
select
  jobid,
  jobname,
  schedule,
  active
from cron.job
order by jobname;

-- Buckets inventory
select
  id,
  name,
  public
from storage.buckets
order by name;

-- Auth users count
select count(*) as auth_users from auth.users;

