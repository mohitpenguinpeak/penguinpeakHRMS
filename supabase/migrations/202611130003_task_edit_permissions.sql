begin;

create or replace function public.guard_task_edit_permissions()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Preserve trusted backend maintenance; enforce permissions for app users.
  if auth.role() = 'service_role' then return new; end if;
  if auth.uid() = old.creator_id then
    if new.creator_id is distinct from old.creator_id then
      raise exception 'Task creator cannot be changed.' using errcode = '42501';
    end if;
    return new;
  end if;
  if auth.uid() = old.assignee_id then
    -- Completion/update timestamps are maintained alongside status changes.
    if (to_jsonb(new) - array['status', 'priority', 'completed_at', 'updated_at'])
       is distinct from
       (to_jsonb(old) - array['status', 'priority', 'completed_at', 'updated_at']) then
      raise exception 'Assignees can change only task status and priority.' using errcode = '42501';
    end if;
    return new;
  end if;
  raise exception 'Only the task creator or assignee can edit this task.' using errcode = '42501';
end;
$$;

revoke all on function public.guard_task_edit_permissions() from public, anon, authenticated;
create trigger enforce_task_edit_permissions before update on public.tasks
  for each row execute function public.guard_task_edit_permissions();

commit;
