begin;
grant delete on public.task_work_logs to authenticated;
create policy task_work_logs_delete_own on public.task_work_logs
  for delete to authenticated
  using (public.has_approved_account() and employee_id = (select auth.uid()));
create policy task_work_logs_delete_owner_only on public.task_work_logs as restrictive
  for delete to authenticated
  using (employee_id = (select auth.uid()));
commit;
