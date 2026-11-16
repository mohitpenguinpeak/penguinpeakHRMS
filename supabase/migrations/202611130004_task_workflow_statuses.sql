begin;

-- Replace only single-column status checks; preserve unrelated constraints.
do $$
declare
  status_column smallint;
  constraint_row record;
begin
  select attnum into status_column from pg_attribute
  where attrelid = 'public.tasks'::regclass and attname = 'status';
  for constraint_row in
    select conname from pg_constraint
    where conrelid = 'public.tasks'::regclass and contype = 'c'
      and conkey = array[status_column]::smallint[]
  loop
    execute format('alter table public.tasks drop constraint %I', constraint_row.conname);
  end loop;
end;
$$;

-- Retain legacy blocked records and the separate acceptance/decline workflow.
alter table public.tasks add constraint tasks_status_check check (
  status in ('todo', 'in_progress', 'completed', 'pending', 'on_hold', 'in_review',
             'pending_acceptance', 'declined', 'blocked')
);

commit;
