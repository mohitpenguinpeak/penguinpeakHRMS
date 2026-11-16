begin;
alter table public.leave_requests add column day_portion text not null default 'full_day';
alter table public.leave_requests add constraint leave_day_portion_valid check (
  (day_portion = 'full_day') or
  (day_portion in ('first_half','second_half') and start_date = end_date and days = 0.5)
);
create or replace function public.apply_for_leave_duration(
  p_leave_type text, p_start_date date, p_end_date date, p_day_portion text, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare applicant public.profiles%rowtype; request_id uuid; actual_days numeric;
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
  if p_day_portion is null or p_day_portion not in ('full_day','first_half','second_half') then raise exception 'Select full day or a half'; end if;
  if p_day_portion <> 'full_day' and p_start_date <> p_end_date then raise exception 'Half-day leave must use a single date'; end if;
  actual_days := case when p_day_portion = 'full_day' then p_end_date - p_start_date + 1 else 0.5 end;
  if nullif(btrim(p_leave_type), '') is null or nullif(btrim(p_reason), '') is null then
    raise exception 'Leave type and reason are required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(applicant.id::text, 1));
  if exists (select 1 from public.leave_requests
    where employee_id = applicant.id and cancelled_at is null and manager_status <> 'rejected' and hr_status <> 'rejected'
      and (case when hr_status = 'approved' then coalesce(approved_start_date,start_date) else start_date end) <= p_end_date
      and (case when hr_status = 'approved' then coalesce(approved_end_date,end_date) else end_date end) >= p_start_date
      and (p_day_portion = 'full_day' or day_portion = 'full_day' or day_portion = p_day_portion)) then
    raise exception 'An active leave request already overlaps these dates';
  end if;
  insert into public.leave_requests(employee_id, manager_id, leave_type, start_date, end_date, days, reason, day_portion)
  values (applicant.id, applicant.manager_id, btrim(p_leave_type), p_start_date, p_end_date, actual_days, btrim(p_reason), p_day_portion)
  returning id into request_id;
  return request_id;
end;
$$;


revoke all on function public.apply_for_leave_duration(text,date,date,text,text) from public, anon;
grant execute on function public.apply_for_leave_duration(text,date,date,text,text) to authenticated;
create or replace function public.review_leave_by_hr_range(
  p_request_id uuid, p_decision text, p_comment text,
  p_approved_start_date date, p_approved_end_date date
) returns void language plpgsql security definer set search_path = '' as $$
declare request public.leave_requests%rowtype; balance public.leave_balances%rowtype;
  first_day date; last_day date; quantity numeric;
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
    quantity := case when request.day_portion <> 'full_day' then 0.5 else last_day - first_day + 1 end;
    if quantity > request.days then raise exception 'Approved quantity exceeds requested days; review legacy request data'; end if;
    select * into balance from public.leave_balances where employee_id = request.employee_id and leave_type = request.leave_type for update;
    if balance.id is null then raise exception 'Configure employee leave balance first'; end if;
    if not balance.is_unlimited and balance.allocated_days - balance.used_days < quantity then raise exception 'Insufficient leave balance'; end if;
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

commit;
