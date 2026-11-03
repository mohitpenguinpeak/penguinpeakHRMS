-- READ ONLY: metadata for existing task/project/time-entry structures.
-- Run as the project owner in SQL Editor; return metadata only, no business rows.
select table_name, column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name in (
  'tasks', 'task_comments', 'projects', 'project_members', 'task_groups',
  'task_time_entries', 'time_entries', 'timesheets', 'timesheet_entries',
  'task_dependencies', 'task_labels', 'sprints', 'epics'
)
order by table_name, ordinal_position;

select c.relname as table_name, k.conname, pg_get_constraintdef(k.oid) as definition
from pg_constraint k join pg_class c on c.oid = k.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in (
  'tasks', 'projects', 'project_members', 'task_time_entries', 'time_entries',
  'timesheets', 'timesheet_entries'
)
order by c.relname, k.conname;

select tablename, indexname, indexdef from pg_indexes
where schemaname = 'public' and tablename in (
  'tasks', 'task_time_entries', 'time_entries', 'timesheets', 'timesheet_entries'
) order by tablename, indexname;

select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relname in (
  'tasks', 'projects', 'project_members', 'task_time_entries', 'time_entries',
  'timesheets', 'timesheet_entries'
) order by c.relname;

select tablename, policyname, roles, cmd, qual, with_check from pg_policies
where schemaname = 'public' and tablename in (
  'tasks', 'projects', 'project_members', 'task_time_entries', 'time_entries',
  'timesheets', 'timesheet_entries'
) order by tablename, policyname;
