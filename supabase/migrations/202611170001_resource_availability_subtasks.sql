begin;

-- One row per active account. Only aggregate hours and leave flags cross
-- task and leave visibility boundaries.
create function public.resource_availability(p_start date, p_days integer)
returns table(id uuid, full_name text, days jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_approved_account() then
    raise exception 'Approved account required' using errcode = '42501';
  end if;
  if p_start is null or p_days is null or p_days not between 1 and 31 then
    raise exception 'Choose a range of 1 to 31 days';
  end if;
  return query with dates as (
    select p_start+i as day from generate_series(0,p_days-1) i union select current_date
  ), bookings as (
    select t.assignee_id, d.day,
      sum(coalesce(nullif(substring(t.description from '\[Booking:\s*([0-9]+\.?[0-9]*)\s*hrs\]')::numeric,0),2)) hours
    from public.tasks t join dates d on coalesce(t.due_date::date,t.created_at::date)=d.day
    where t.status not in ('completed','declined') group by t.assignee_id,d.day
  )
  select p.id,p.full_name::text,jsonb_object_agg(d.day::text,jsonb_build_object(
    'hours',coalesce(b.hours,0),'leave',exists(select 1 from public.leave_requests l
      where l.employee_id=p.id and l.cancelled_at is null and l.manager_status='approved'
        and l.hr_status='approved' and d.day between coalesce(l.approved_start_date,l.start_date)
        and coalesce(l.approved_end_date,l.end_date))))
  from public.profiles p cross join dates d left join bookings b on b.assignee_id=p.id and b.day=d.day
  where p.approval_status='approved' and p.removed_at is null
  group by p.id,p.full_name order by p.full_name,p.id;
end;
$$;
revoke all on function public.resource_availability(date,integer) from public,anon;
grant execute on function public.resource_availability(date,integer) to authenticated;

alter table public.tasks add column parent_task_id uuid references public.tasks(id) on delete set null;
create index tasks_parent_task on public.tasks(parent_task_id) where parent_task_id is not null;

create function public.check_subtask_parent() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='UPDATE' then
    if new.parent_task_id is distinct from old.parent_task_id
        and not (new.parent_task_id is null and pg_trigger_depth()>1) then
      raise exception 'A task cannot be reparented';
    end if;
  elsif new.parent_task_id is not null then
    if auth.uid() is null or new.creator_id is distinct from auth.uid() or not public.has_approved_account() then
      raise exception 'Approved assignee required' using errcode='42501';
    end if;
    perform 1 from public.tasks where id=new.parent_task_id and assignee_id=auth.uid() for share;
    if not found then raise exception 'Only the parent task assignee can create a subtask' using errcode='42501'; end if;
    if not exists(select 1 from public.profiles where id=new.assignee_id and approval_status='approved' and removed_at is null) then
      raise exception 'Choose an active assignee';
    end if;
  end if;
  return new;
end;
$$;
create trigger check_subtask_parent before insert or update of parent_task_id on public.tasks
for each row execute function public.check_subtask_parent();
create policy tasks_insert_subtask on public.tasks for insert to authenticated
with check(parent_task_id is not null and creator_id=auth.uid() and public.has_approved_account());
create policy tasks_read_my_subtasks on public.tasks for select to authenticated
using(parent_task_id is not null and auth.uid() in (creator_id,assignee_id) and public.has_approved_account());
commit;
