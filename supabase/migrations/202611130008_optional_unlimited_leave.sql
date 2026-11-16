begin;
alter table public.leave_balances add column is_unlimited boolean not null default false;
alter table public.leave_balances drop constraint if exists leave_balances_used_not_over_allocated;
alter table public.leave_balances add constraint leave_balances_used_not_over_allocated
  check (is_unlimited or used_days <= allocated_days);

create or replace function public.set_employee_leave_allocation(
  p_employee_id uuid, p_leave_type text, p_allocated_days numeric, p_is_unlimited boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare used numeric;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'hr' and approval_status = 'approved') then
    raise exception 'Only approved HR can manage balances' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p_employee_id and role in ('employee','hr') and approval_status = 'approved') then
    raise exception 'Choose an approved employee or HR account';
  end if;
  if p_is_unlimited is null or nullif(btrim(p_leave_type), '') is null then raise exception 'Choose a leave type and allocation mode'; end if;
  if not p_is_unlimited and (p_allocated_days is null or p_allocated_days < 0 or p_allocated_days::text in ('NaN','Infinity','-Infinity')) then
    raise exception 'Enter a finite non-negative allocation';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_employee_id::text || ':' || btrim(p_leave_type), 0));
  select used_days into used from public.leave_balances where employee_id = p_employee_id and leave_type = btrim(p_leave_type) for update;
  if not p_is_unlimited and p_allocated_days < coalesce(used,0) then raise exception 'Allocation cannot be below days already used'; end if;
  insert into public.leave_balances(employee_id, leave_type, allocated_days, used_days, is_unlimited)
    values(p_employee_id, btrim(p_leave_type), case when p_is_unlimited then coalesce(used,0) else p_allocated_days end, coalesce(used,0), p_is_unlimited)
    on conflict (employee_id, leave_type) do update set
      allocated_days = case when excluded.is_unlimited then public.leave_balances.allocated_days else excluded.allocated_days end,
      is_unlimited = excluded.is_unlimited, updated_at = now();
end;
$$;
revoke all on function public.set_employee_leave_allocation(uuid,text,numeric,boolean) from public, anon;
grant execute on function public.set_employee_leave_allocation(uuid,text,numeric,boolean) to authenticated;

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
