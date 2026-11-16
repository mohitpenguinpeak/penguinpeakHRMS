begin;
create table public.task_work_logs (
  id text primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  employee_id uuid not null references public.profiles(id),
  task_title text not null,
  logged_seconds integer not null check (logged_seconds > 0),
  logged_hours_fmt text not null,
  note text not null default '',
  date date not null,
  created_at timestamptz not null default now()
);
create index task_work_logs_task_date on public.task_work_logs(task_id, created_at);
alter table public.task_work_logs enable row level security;
grant select, insert on public.task_work_logs to authenticated;
create policy task_work_logs_read on public.task_work_logs for select to authenticated
using (public.has_approved_account() and exists (
  select 1 from public.tasks t where t.id = task_id
  and (t.creator_id = auth.uid() or t.assignee_id = auth.uid())
));
create policy task_work_logs_insert on public.task_work_logs for insert to authenticated
with check (public.has_approved_account() and employee_id = auth.uid() and exists (
  select 1 from public.tasks t where t.id = task_id and t.assignee_id = auth.uid()
  and t.status not in ('completed', 'declined', 'pending_acceptance')
));
commit;
