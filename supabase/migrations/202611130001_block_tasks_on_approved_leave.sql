-- The matrix books tasks on due_date, falling back to created_at.
begin;

create or replace function public.guard_task_assignment_on_leave()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_day date;
begin
  -- Status/comment changes must remain possible for existing bookings.
  if tg_op = 'UPDATE' then
    if new.assignee_id is not distinct from old.assignee_id
       and new.due_date is not distinct from old.due_date
       and new.created_at is not distinct from old.created_at then
      return new;
    end if;
  end if;

  booking_day := coalesce(new.due_date::date, new.created_at::date, current_date);
  if exists (
    select 1 from public.leave_requests l
    where l.employee_id = new.assignee_id
      and l.manager_status = 'approved'
      and l.hr_status = 'approved'
      and l.cancelled_at is null
      and booking_day between coalesce(l.approved_start_date, l.start_date)
                          and coalesce(l.approved_end_date, l.end_date)
  ) then
    raise exception 'Cannot assign task: employee is on approved leave on %. Choose another date or assignee.', booking_day
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_task_assignment_on_leave() from public, anon, authenticated;
create trigger enforce_task_assignment_leave
before insert or update of assignee_id, due_date, created_at on public.tasks
for each row execute function public.guard_task_assignment_on_leave();

commit;
