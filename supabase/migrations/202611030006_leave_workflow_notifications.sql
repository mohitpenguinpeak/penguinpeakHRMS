-- Verified existing full-day approval RPC contracts; preserve final-only deduction.
-- Requires 004/005. No partial leave or accrual policy is invented here.
begin;
alter table public.notifications
  add column event_type text not null default 'leave.applied',
  add column category text not null default 'leave',
  add column priority text not null default 'normal',
  add column destination text not null default 'leave',
  add column event_key text;
update public.notifications set event_key = 'leave:' || leave_request_id || ':applied';
alter table public.notifications alter column event_key set not null;
alter table public.notifications
  drop constraint notifications_recipient_id_leave_request_id_key;
create unique index notifications_recipient_event_unique
  on public.notifications(recipient_id, event_key);

create or replace function public.apply_for_leave(
  p_leave_type text, p_start_date date, p_end_date date, p_days numeric, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare applicant public.profiles%rowtype; request_id uuid; actual_days integer;
begin
  select * into applicant from public.profiles
    where id = auth.uid() and approval_status = 'approved';
  if applicant.id is null then raise exception 'Approved account required' using errcode = '42501'; end if;
  if applicant.manager_id is null or applicant.manager_id = applicant.id
    or not exists (select 1 from public.profiles where id = applicant.manager_id and approval_status = 'approved') then
    raise exception 'Ask HR to assign a different approved reporting manager';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Please select valid leave dates';
  end if;
  actual_days := p_end_date - p_start_date + 1;
  -- Existing UI and schema use full calendar days. Working-day/half-day policy is
  -- a separate feature; never accept an arbitrary client-supplied quantity.
  if p_days is null or p_days <> actual_days then raise exception 'Leave days must match the selected full-day date range'; end if;
  if nullif(btrim(p_leave_type), '') is null or nullif(btrim(p_reason), '') is null then
    raise exception 'Leave type and reason are required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(applicant.id::text, 1));
  if exists (select 1 from public.leave_requests
    where employee_id = applicant.id and manager_status <> 'rejected' and hr_status <> 'rejected'
      and start_date <= p_end_date and end_date >= p_start_date) then
    raise exception 'An active leave request already overlaps these dates';
  end if;
  insert into public.leave_requests(employee_id, manager_id, leave_type, start_date, end_date, days, reason)
  values (applicant.id, applicant.manager_id, btrim(p_leave_type), p_start_date, p_end_date, actual_days, btrim(p_reason))
  returning id into request_id;
  return request_id;
end;
$$;

create or replace function public.review_leave_by_manager(
  p_request_id uuid, p_decision text, p_comment text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare request public.leave_requests%rowtype;
begin
  if not public.has_approved_account() then raise exception 'Approved account required' using errcode = '42501'; end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then raise exception 'Choose approved or rejected'; end if;
  select * into request from public.leave_requests where id = p_request_id for update;
  if request.id is null then raise exception 'Leave request not found'; end if;
  if request.manager_id is distinct from auth.uid() or request.employee_id = auth.uid() then
    raise exception 'Only the assigned reporting manager may review another employee''s request' using errcode = '42501';
  end if;
  if request.manager_status <> 'pending' or request.hr_status <> 'pending' then raise exception 'Request already reviewed'; end if;
  update public.leave_requests set manager_status = p_decision,
    manager_comment = nullif(btrim(coalesce(p_comment, '')), ''), reviewed_by_manager_at = now()
    where id = p_request_id;
end;
$$;

create or replace function public.review_leave_by_hr(
  p_request_id uuid, p_decision text, p_comment text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare request public.leave_requests%rowtype; balance public.leave_balances%rowtype;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and approval_status = 'approved' and role = 'hr') then
    raise exception 'Only approved HR may give final approval' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then raise exception 'Choose approved or rejected'; end if;
  select * into request from public.leave_requests where id = p_request_id for update;
  if request.id is null then raise exception 'Leave request not found'; end if;
  if request.employee_id = auth.uid() then raise exception 'You cannot finally approve your own leave' using errcode = '42501'; end if;
  if request.manager_status <> 'approved' or request.hr_status <> 'pending' then raise exception 'Request is not awaiting HR'; end if;
  if p_decision = 'approved' then
    select * into balance from public.leave_balances where employee_id = request.employee_id and leave_type = request.leave_type for update;
    if balance.id is null then raise exception 'Configure employee leave balance first'; end if;
    if balance.allocated_days - balance.used_days < request.days then raise exception 'Insufficient leave balance'; end if;
    update public.leave_balances set used_days = used_days + request.days, updated_at = now() where id = balance.id;
  end if;
  update public.leave_requests set hr_status = p_decision,
    hr_comment = nullif(btrim(coalesce(p_comment, '')), ''), reviewed_by_hr_at = now()
    where id = p_request_id;
end;
$$;

-- Keep the deployed trigger name/function contract; newly submitted leave goes
-- to its assigned manager. HR is notified only after manager approval.
create or replace function public.notify_leave_application()
returns trigger language plpgsql security definer set search_path = '' as $$
declare employee_name text;
begin
  select coalesce(nullif(btrim(full_name), ''), 'Employee') into employee_name from public.profiles where id = new.employee_id;
  insert into public.notifications(recipient_id, leave_request_id, title, body, event_type, event_key)
  select p.id, new.id::text, 'Leave request requires approval',
    employee_name || ' requested ' || new.leave_type || ' leave from ' || new.start_date || ' to ' || new.end_date || '.',
    'leave.applied', 'leave:' || new.id || ':applied'
  from public.profiles p where p.id = new.manager_id and p.approval_status = 'approved'
  on conflict (recipient_id, event_key) do nothing;
  return new;
end;
$$;

create or replace function public.notify_leave_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare phase text; decision text; employee_name text;
begin
  if new.manager_status is distinct from old.manager_status then
    phase := 'manager'; decision := new.manager_status;
  elsif new.hr_status is distinct from old.hr_status then
    phase := 'hr'; decision := new.hr_status;
  else return new;
  end if;
  if decision not in ('approved', 'rejected') then return new; end if;
  insert into public.notifications(recipient_id, leave_request_id, title, body, event_type, event_key)
  values (new.employee_id, new.id::text, 'Leave request update',
    'Your leave from ' || new.start_date || ' to ' || new.end_date || ' was ' || decision || ' by ' ||
      case when phase = 'hr' then 'HR.' when decision = 'approved' then 'your manager; awaiting HR.' else 'your manager.' end,
    'leave.' || phase || '.' || decision, 'leave:' || new.id || ':' || phase || ':' || decision)
  on conflict (recipient_id, event_key) do nothing;
  if phase = 'manager' and decision = 'approved' then
    select coalesce(nullif(btrim(full_name), ''), 'Employee') into employee_name from public.profiles where id = new.employee_id;
    insert into public.notifications(recipient_id, leave_request_id, title, body, event_type, event_key)
    select p.id, new.id::text, 'Leave awaiting HR approval', employee_name || '''s manager approved leave from ' || new.start_date || ' to ' || new.end_date || '. Review the request.',
      'leave.hr.pending', 'leave:' || new.id || ':hr:pending'
    from public.profiles p where p.role = 'hr' and p.approval_status = 'approved' and p.id <> new.employee_id
    on conflict (recipient_id, event_key) do nothing;
  end if;
  return new;
end;
$$;
create trigger leave_review_notifications after update of manager_status, hr_status
  on public.leave_requests for each row execute function public.notify_leave_review();

revoke all on function public.notify_leave_application(), public.notify_leave_review() from public, anon, authenticated;
revoke all on function public.apply_for_leave(text,date,date,numeric,text),
  public.review_leave_by_manager(uuid,text,text), public.review_leave_by_hr(uuid,text,text) from public, anon;
grant execute on function public.apply_for_leave(text,date,date,numeric,text),
  public.review_leave_by_manager(uuid,text,text), public.review_leave_by_hr(uuid,text,text) to authenticated;
commit;
