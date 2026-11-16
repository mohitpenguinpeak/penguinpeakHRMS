begin;
-- Allow assignees to backfill time after completing a task.
drop policy task_work_logs_insert on public.task_work_logs;
create policy task_work_logs_insert on public.task_work_logs for insert to authenticated
with check (public.has_approved_account() and employee_id = auth.uid() and exists (
  select 1 from public.tasks t where t.id = task_id and t.assignee_id = auth.uid()
  and t.status not in ('declined', 'pending_acceptance')
));
commit;
