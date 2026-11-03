-- Core HR: one contiguous approved date range, future-leave cancellation and audit.
-- Depends on 004–006. Full calendar-day policy preserved; no half-day/accrual rules.
begin;
alter table public.leave_requests
  add column approved_start_date date,
  add column approved_end_date date,
  add column approved_days numeric,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid references public.profiles(id),
  add column cancellation_reason text;
update public.leave_requests set approved_start_date = start_date,
  approved_end_date = end_date, approved_days = days where hr_status = 'approved';
alter table public.leave_requests add constraint leave_approved_range_valid check (
  (approved_start_date is null and approved_end_date is null and approved_days is null)
  or (approved_start_date is not null and approved_end_date is not null and approved_days is not null
    and approved_start_date >= start_date and approved_end_date <= end_date
    and approved_start_date <= approved_end_date and approved_days > 0 and approved_days <= days)
);
create index leave_active_employee_dates_idx on public.leave_requests(employee_id, start_date, end_date)
  where cancelled_at is null;

create table public.leave_request_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.leave_requests(id),
  actor_id uuid references public.profiles(id),
  action text not null,
  created_at timestamptz not null default now(),
  details jsonb not null
);
create index leave_history_request_date_idx on public.leave_request_history(request_id, created_at);
alter table public.leave_request_history enable row level security;
revoke all on public.leave_request_history from public, anon, authenticated;
grant select on public.leave_request_history to authenticated;
create policy leave_history_read_relevant on public.leave_request_history for select to authenticated
  using (public.has_approved_account() and exists (select 1 from public.leave_requests r
    where r.id = request_id and (r.employee_id = auth.uid() or r.manager_id = auth.uid()
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'hr' and p.approval_status = 'approved'))));

create or replace function public.audit_leave_request_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare event text;
begin
  if tg_op = 'INSERT' then event := 'applied';
  elsif new.cancelled_at is distinct from old.cancelled_at then event := 'cancelled';
  elsif new.hr_status is distinct from old.hr_status then
    event := 'hr.' || new.hr_status;
  elsif new.manager_status is distinct from old.manager_status then
    event := 'manager.' || new.manager_status;
  else return new;
  end if;
  insert into public.leave_request_history(request_id, actor_id, action, details)
  values (new.id, auth.uid(), event, jsonb_build_object(
    'requested_start', new.start_date, 'requested_end', new.end_date, 'requested_days', new.days,
    'approved_start', new.approved_start_date, 'approved_end', new.approved_end_date, 'approved_days', new.approved_days,
    'manager_status', new.manager_status, 'hr_status', new.hr_status,
    'manager_comment', new.manager_comment, 'hr_comment', new.hr_comment,
    'cancellation_reason', new.cancellation_reason));
  return new;
end;
$$;
revoke all on function public.audit_leave_request_change() from public, anon, authenticated;
create trigger leave_request_audit after insert or update on public.leave_requests
  for each row execute function public.audit_leave_request_change();

-- Single authoritative HR review implementation, existing 3-argument RPC delegates.
create or replace function public.review_leave_by_hr_range(
  p_request_id uuid, p_decision text, p_comment text,
  p_approved_start_date date, p_approved_end_date date
) returns void language plpgsql security definer set search_path = '' as $$
declare request public.leave_requests%rowtype; balance public.leave_balances%rowtype;
  first_day date; last_day date; quantity integer;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and approval_status = 'approved' and role = 'hr') then
    raise exception 'Only approved HR may give final approval' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then raise exception 'Choose approved or rejected'; end if;
  select * into request from public.leave_requests where id = p_request_id for update;
  if request.id is null then raise exception 'Leave request not found'; end if;
  if request.employee_id = auth.uid() then raise exception 'You cannot finally approve your own leave' using errcode = '42501'; end if;
  if request.cancelled_at is not null or request.manager_status <> 'approved' or request.hr_status <> 'pending' then
    raise exception 'Request is not awaiting HR';
  end if;
  if p_decision = 'approved' then
    if (p_approved_start_date is null) <> (p_approved_end_date is null) then raise exception 'Select both approved dates'; end if;
    first_day := coalesce(p_approved_start_date, request.start_date);
    last_day := coalesce(p_approved_end_date, request.end_date);
    if first_day < request.start_date or last_day > request.end_date or last_day < first_day then
      raise exception 'Approved range must be within the requested dates';
    end if;
    quantity := last_day - first_day + 1;
    if quantity > request.days then raise exception 'Approved quantity exceeds requested days; review legacy request data'; end if;
    select * into balance from public.leave_balances where employee_id = request.employee_id and leave_type = request.leave_type for update;
    if balance.id is null then raise exception 'Configure employee leave balance first'; end if;
    if balance.allocated_days - balance.used_days < quantity then raise exception 'Insufficient leave balance'; end if;
    update public.leave_balances set used_days = used_days + quantity, updated_at = now() where id = balance.id;
  elsif p_approved_start_date is not null or p_approved_end_date is not null then
    raise exception 'Rejected leave cannot have an approved range';
  end if;
  update public.leave_requests set hr_status = p_decision,
    hr_comment = nullif(btrim(coalesce(p_comment, '')), ''), reviewed_by_hr_at = now(),
    approved_start_date = first_day, approved_end_date = last_day, approved_days = quantity
    where id = p_request_id;
end;
$$;
create or replace function public.review_leave_by_hr(
  p_request_id uuid, p_decision text, p_comment text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.review_leave_by_hr_range(p_request_id, p_decision, p_comment, null, null);
end;
$$;

create or replace function public.cancel_leave_request(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare request public.leave_requests%rowtype; balance public.leave_balances%rowtype;
  cancel_time timestamptz := now();
begin
  if not public.has_approved_account() then raise exception 'Approved account required' using errcode = '42501'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Cancellation reason is required'; end if;
  select * into request from public.leave_requests where id = p_request_id for update;
  if request.id is null then raise exception 'Leave request not found'; end if;
  if request.employee_id <> auth.uid() and not public.can_manage_employee_profiles() then
    raise exception 'Only the applicant or HR administration may cancel leave' using errcode = '42501';
  end if;
  if request.cancelled_at is not null or request.manager_status = 'rejected' or request.hr_status = 'rejected' then
    raise exception 'Request is already cancelled or rejected';
  end if;
  -- A future-only policy avoids refunding days already taken; timestamps remain
  -- server-owned. Company timezone configuration is a subsequent policy feature.
  if coalesce(request.approved_start_date, request.start_date) <= current_date then
    raise exception 'Only future leave may be cancelled here; contact HR for historical correction';
  end if;
  if request.hr_status = 'approved' then
    select * into balance from public.leave_balances where employee_id = request.employee_id and leave_type = request.leave_type for update;
    if balance.id is null or request.approved_days is null or balance.used_days < request.approved_days then
      raise exception 'Balance reconciliation required before cancellation';
    end if;
    update public.leave_balances set used_days = used_days - request.approved_days, updated_at = now() where id = balance.id;
  end if;
  update public.leave_requests set cancelled_at = cancel_time, cancelled_by = auth.uid(), cancellation_reason = btrim(p_reason)
    where id = p_request_id;
  insert into public.notifications(recipient_id, leave_request_id, title, body, event_type, event_key)
  select recipients.id, request.id::text, 'Leave request cancelled',
    'Leave from ' || coalesce(request.approved_start_date,request.start_date) || ' to ' || coalesce(request.approved_end_date,request.end_date) || ' was cancelled.',
    'leave.cancelled', 'leave:' || request.id || ':cancelled'
  from (select request.employee_id as id union select request.manager_id union
    select p.id from public.profiles p where p.role = 'hr' and p.approval_status = 'approved' and request.manager_status = 'approved') recipients
  join public.profiles p on p.id = recipients.id and p.approval_status = 'approved'
  on conflict (recipient_id, event_key) do nothing;
end;
$$;
revoke all on function public.review_leave_by_hr_range(uuid,text,text,date,date), public.cancel_leave_request(uuid,text) from public, anon;
grant execute on function public.review_leave_by_hr_range(uuid,text,text,date,date), public.cancel_leave_request(uuid,text) to authenticated;
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
    where employee_id = applicant.id and cancelled_at is null and manager_status <> 'rejected' and hr_status <> 'rejected'
      and (case when hr_status = 'approved' then coalesce(approved_start_date,start_date) else start_date end) <= p_end_date
      and (case when hr_status = 'approved' then coalesce(approved_end_date,end_date) else end_date end) >= p_start_date) then
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
  if request.cancelled_at is not null or request.manager_status <> 'pending' or request.hr_status <> 'pending' then raise exception 'Request already reviewed'; end if;
  update public.leave_requests set manager_status = p_decision,
    manager_comment = nullif(btrim(coalesce(p_comment, '')), ''), reviewed_by_manager_at = now()
    where id = p_request_id;
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
    'Your leave from ' || coalesce(new.approved_start_date,new.start_date) || ' to ' || coalesce(new.approved_end_date,new.end_date) || ' was ' || case when phase = 'hr' and decision = 'approved' and new.approved_days < new.days then 'partially approved (' || new.approved_days || ' days)' else decision end || ' by ' ||
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

commit;
