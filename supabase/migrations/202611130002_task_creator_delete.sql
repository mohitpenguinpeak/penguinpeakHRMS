begin;

-- Restrict existing DELETE policies as well as granting creator access.
create policy tasks_delete_creator on public.tasks
  for delete to authenticated using (creator_id = (select auth.uid()));
create policy tasks_delete_creator_only on public.tasks as restrictive
  for delete to authenticated using (creator_id = (select auth.uid()));
grant delete on public.tasks to authenticated;

-- Remove child comments in the same transaction, including comments by others.
create or replace function public.delete_task_comments_with_task()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.task_comments where task_id = old.id;
  return old;
end;
$$;
revoke all on function public.delete_task_comments_with_task() from public, anon, authenticated;
create trigger delete_task_comments_before_task
  before delete on public.tasks for each row
  execute function public.delete_task_comments_with_task();

commit;
