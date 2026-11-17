begin;

-- Live, read-only scorecards: no duplicated employee records or cron dependency.
create or replace function public.performance_scorecards(
  p_period text default 'monthly', p_anchor date default null,
  p_employee uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  actor public.profiles%rowtype;
  zone text; today date; anchor_day date; first_day date; last_day date;
  result jsonb;
begin
  select * into actor from public.profiles where id = auth.uid();
  if actor.id is null or actor.approval_status is distinct from 'approved'
    or coalesce(actor.role,'') not in ('employee','management','hr','admin','super_admin') then
    raise exception 'Approved account required' using errcode = '42501';
  end if;
  select s.timezone into zone from public.company_attendance_settings s limit 1;
  zone := coalesce(nullif(zone, ''), 'UTC');
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = zone) then zone := 'UTC'; end if;
  today := (now() at time zone zone)::date;
  anchor_day := coalesce(p_anchor, today);
  if anchor_day > today then raise exception 'Future performance periods are unavailable'; end if;
  if p_period is null or p_period not in ('daily','weekly','monthly','quarterly','annually') then
    raise exception 'Invalid performance period';
  end if;
  first_day := case p_period
    when 'daily' then anchor_day
    when 'weekly' then date_trunc('week', anchor_day)::date
    when 'monthly' then date_trunc('month', anchor_day)::date
    when 'quarterly' then date_trunc('quarter', anchor_day)::date
    else date_trunc('year', anchor_day)::date end;
  last_day := case p_period
    when 'daily' then first_day
    when 'weekly' then first_day + 6
    when 'monthly' then (first_day + interval '1 month - 1 day')::date
    when 'quarterly' then (first_day + interval '3 months - 1 day')::date
    else (first_day + interval '1 year - 1 day')::date end;
  if p_employee is not null and not exists (
    select 1 from public.profiles p where p.id = p_employee and p.approval_status = 'approved'
      and (p.id = actor.id or actor.role in ('hr','admin','super_admin')
        or (actor.role = 'management' and p.manager_id = actor.id))
  ) then raise exception 'Performance access denied' using errcode = '42501'; end if;

  with employees as (
    select p.id, p.full_name, p.department,
      greatest(first_day, coalesce(p.joining_date::date, (p.created_at at time zone zone)::date, first_day)) starts
    from public.profiles p where p.approval_status = 'approved'
      and (p_employee is null or p.id = p_employee)
      and (p.id = actor.id or actor.role in ('hr','admin','super_admin')
        or (actor.role = 'management' and p.manager_id = actor.id))
  ), days as (
    select e.id, d::date work_day from employees e
    cross join lateral generate_series(e.starts::timestamp, least(last_day,today)::timestamp, interval '1 day') d
    where extract(isodow from d) between 1 and 5
      and not exists (select 1 from public.holidays h where h.holiday_date = d::date)
  ), daily_attendance as (
    select d.id, d.work_day,
      -- Count each approved half at most once, including overlapping legacy leave.
      greatest(0, 1 - coalesce((select coalesce(max(case when l.day_portion in ('full_day','first_half') then 0.5 else 0 end),0)
          + coalesce(max(case when l.day_portion in ('full_day','second_half') then 0.5 else 0 end),0)
        from public.leave_requests l where l.employee_id = d.id
          and l.manager_status = 'approved' and l.hr_status = 'approved' and l.cancelled_at is null
          and d.work_day between coalesce(l.approved_start_date,l.start_date) and coalesce(l.approved_end_date,l.end_date)),0)) required,
      coalesce(a.credit,0) credit, coalesce(a.present,false) present, coalesce(a.late,false) late
    from days d left join lateral (
      select max(case when r.check_in is not null then case when lower(r.status) = 'half day' then 0.5 else 1 end else 0 end) credit,
        bool_or(r.check_in is not null) present,
        bool_or(r.check_in is not null and (coalesce(r.late_minutes,0) > 0 or lower(r.status) = 'late')) late
      from public.attendance_records r where r.employee_id = d.id and r.attendance_date = d.work_day
    ) a on true
  ), attendance as (
    select id, sum(required) expected_days, sum(least(required,credit)) attended_days,
      count(*) filter (where required = 1 and present) punctual_days,
      count(*) filter (where required = 1 and present and not late) on_time_days
    from daily_attendance
    -- Missing punches today are not absences before the day has finished.
    where work_day < today or present
    group by id
  ), task_facts as (
    select e.id, t.status, t.due_date::date due_day,
      (t.completed_at at time zone zone)::date completed_day
    from employees e join public.tasks t on t.assignee_id = e.id
    where t.status not in ('declined','pending_acceptance')
      and ((t.due_date::date between e.starts and least(last_day,today))
        or (t.due_date is null and t.status = 'completed'
          and (t.completed_at at time zone zone)::date between e.starts and least(last_day,today)))
  ), tasks as (
    select id, count(*) task_count,
      count(*) filter (where status = 'completed' and (completed_day is null or completed_day <= least(last_day,today))) completed_tasks,
      count(*) filter (where due_day is not null and not (status = 'completed' and completed_day is null)) dated_tasks,
      count(*) filter (where due_day is not null and status = 'completed' and completed_day <= due_day) on_time_tasks,
      count(*) filter (where status = 'completed' and completed_day is null) unknown_completion_dates
    from task_facts group by id
  ), facts as (
    select e.id, e.full_name, e.department,
      coalesce(t.task_count,0) task_count, coalesce(t.completed_tasks,0) completed_tasks,
      coalesce(t.dated_tasks,0) dated_tasks, coalesce(t.on_time_tasks,0) on_time_tasks,
      coalesce(t.unknown_completion_dates,0) unknown_completion_dates,
      coalesce(a.expected_days,0) expected_days, coalesce(a.attended_days,0) attended_days,
      coalesce(a.punctual_days,0) punctual_days, coalesce(a.on_time_days,0) on_time_days
    from employees e left join tasks t on t.id = e.id left join attendance a on a.id = e.id
  ), rates as (
    select *, 100.0 * completed_tasks / nullif(task_count,0) completion,
      100.0 * on_time_tasks / nullif(dated_tasks,0) delivery,
      100.0 * attended_days / nullif(expected_days,0) attendance,
      100.0 * on_time_days / nullif(punctual_days,0) punctuality
    from facts
  ), scored as (
    select *, (case when completion is not null then 50 else 0 end
      + case when delivery is not null then 20 else 0 end
      + case when attendance is not null then 20 else 0 end
      + case when punctuality is not null then 10 else 0 end) available_weight
    from rates
  ) select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('score',
      round((coalesce(completion*50,0) + coalesce(delivery*20,0)
        + coalesce(attendance*20,0) + coalesce(punctuality*10,0)) / nullif(available_weight,0),1))
      order by s.full_name, s.id),'[]'::jsonb) into result from scored s;
  return jsonb_build_object('period',p_period,'start',first_day,'end',last_day,
    'today',today,'timezone',zone,'provisional',last_day >= today,
    'calculated_at',now(),'matrix_version','v1','employees',result);
end;
$$;
revoke all on function public.performance_scorecards(text,date,uuid) from public, anon;
grant execute on function public.performance_scorecards(text,date,uuid) to authenticated;

create index if not exists performance_tasks_assignee_due on public.tasks(assignee_id,due_date);
create index if not exists performance_attendance_employee_date on public.attendance_records(employee_id,attendance_date);

commit;
