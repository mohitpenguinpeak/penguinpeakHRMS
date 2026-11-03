-- ISOLATED TEST DATABASE ONLY: supplied business function bodies for regression checks.
CREATE OR REPLACE FUNCTION public.apply_for_leave(p_leave_type text, p_start_date date, p_end_date date, p_days numeric, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_profile public.profiles%rowtype;
  new_request_id uuid;
begin
  select * into caller_profile
  from public.profiles
  where id = (select auth.uid())
    and approval_status = 'approved';

  if caller_profile.id is null then
    raise exception 'Only approved employees can apply for leave';
  end if;
  if caller_profile.manager_id is null then
    raise exception 'Ask HR to assign your reporting manager before applying for leave';
  end if;
  if caller_profile.manager_id = caller_profile.id then
    raise exception 'You cannot report to yourself';
  end if;
  if p_leave_type is null or length(trim(p_leave_type)) = 0 then
    raise exception 'Leave type is required';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Please select valid leave dates';
  end if;
  if p_days is null or p_days <= 0 then
    raise exception 'Leave days must be greater than zero';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Please enter a reason for leave';
  end if;

  insert into public.leave_requests (
    employee_id, manager_id, leave_type, start_date, end_date, days, reason
  ) values (
    caller_profile.id, caller_profile.manager_id, trim(p_leave_type),
    p_start_date, p_end_date, p_days, trim(p_reason)
  ) returning id into new_request_id;

  return new_request_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_employee_role(p_user_id uuid, p_role text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_role text;
begin
  select p.role
  into caller_role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.approval_status = 'approved';

  if caller_role not in ('admin', 'super_admin')
     or caller_role is null then
    raise exception 'Only an approved Admin can assign roles';
  end if;

  if p_role not in ('admin', 'management', 'employee', 'hr') then
    raise exception 'Invalid role';
  end if;

  if p_user_id = (select auth.uid()) then
    raise exception 'You cannot change your own role';
  end if;

  update public.profiles
  set role = p_role
  where id = p_user_id;

  if not found then
    raise exception 'Employee profile not found';
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.can_manage_employee_profiles()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'super_admin', 'hr')
  );
$function$
;
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.profiles (id, full_name, approval_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'pending'
  );

  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.is_approved_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.approval_status = 'approved'
  );
$function$
;
CREATE OR REPLACE FUNCTION public.is_hr_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('hr', 'admin', 'super_admin')
      and approval_status = 'approved'
  );
$function$
;
CREATE OR REPLACE FUNCTION public.notify_leave_application()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  applicant public.profiles%rowtype;
begin
  select * into applicant from public.profiles where id = new.employee_id;
  insert into public.notifications (recipient_id, leave_request_id, title, body)
  select p.id, new.id::text, 'New leave application',
    coalesce(nullif(trim(applicant.full_name), ''), 'An employee') ||
    ' applied for ' || new.leave_type || ' leave from ' ||
    new.start_date::text || ' to ' || new.end_date::text || '.'
  from public.profiles p
  where p.approval_status = 'approved'
    and (lower(p.role) = 'hr' or p.id = applicant.manager_id)
  on conflict (recipient_id, leave_request_id) do nothing;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.register_push_token(p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'Invalid push registration';
  end if;
  insert into public.push_tokens(token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end;
$function$
;
CREATE OR REPLACE FUNCTION public.review_employee(p_user_id uuid, p_approval_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_role text;
begin
  select p.role
  into caller_role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.approval_status = 'approved';

  if caller_role not in ('hr', 'admin', 'super_admin')
     or caller_role is null then
    raise exception 'You are not allowed to review employees';
  end if;

  if p_approval_status not in ('approved', 'rejected') then
    raise exception 'Invalid approval status';
  end if;

  if p_user_id = (select auth.uid()) then
    raise exception 'You cannot review your own account';
  end if;

  update public.profiles
  set approval_status = p_approval_status
  where id = p_user_id;
  
  if not found then
    raise exception 'Employee profile not found';
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.review_leave_by_hr(p_request_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller public.profiles%rowtype;
  leave_row public.leave_requests%rowtype;
  balance_row public.leave_balances%rowtype;
begin
  select * into caller from public.profiles
  where id = (select auth.uid())
    and approval_status = 'approved'
    and role = 'hr';
  if caller.id is null then raise exception 'Only approved HR can give final leave approval'; end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  select * into leave_row from public.leave_requests
  where id = p_request_id for update;
  if leave_row.id is null then raise exception 'Leave request not found'; end if;
  if leave_row.employee_id = (select auth.uid()) then
    raise exception 'You cannot give final HR approval to your own leave request';
  end if;
  if leave_row.manager_status <> 'approved' or leave_row.hr_status <> 'pending' then
    raise exception 'This request is not waiting for HR final approval';
  end if;

  if p_decision = 'approved' then
    select * into balance_row from public.leave_balances
    where employee_id = leave_row.employee_id
      and leave_type = leave_row.leave_type
    for update;

    if balance_row.id is null then
      raise exception 'HR must configure a leave balance for this employee and leave type first';
    end if;
    if balance_row.allocated_days - balance_row.used_days < leave_row.days then
      raise exception 'Insufficient leave balance. HR must adjust the balance before approval';
    end if;

    update public.leave_balances
    set used_days = used_days + leave_row.days, updated_at = now()
    where id = balance_row.id;
  end if;

  update public.leave_requests
  set hr_status = p_decision,
      hr_comment = nullif(trim(coalesce(p_comment, '')), ''),
      reviewed_by_hr_at = now()
  where id = p_request_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.review_leave_by_manager(p_request_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  leave_row public.leave_requests%rowtype;
  caller public.profiles%rowtype;
begin
  select * into caller from public.profiles
  where id = (select auth.uid()) and approval_status = 'approved';
  if caller.id is null then raise exception 'An approved account is required'; end if;

  select * into leave_row from public.leave_requests
  where id = p_request_id for update;
  if leave_row.id is null then raise exception 'Leave request not found'; end if;
  if leave_row.manager_id <> (select auth.uid()) then
    raise exception 'Only the assigned reporting manager can review this request';
  end if;
  if leave_row.manager_status <> 'pending' then
    raise exception 'This request has already been reviewed by the manager';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  update public.leave_requests
  set manager_status = p_decision,
      manager_comment = nullif(trim(coalesce(p_comment, '')), ''),
      reviewed_by_manager_at = now()
  where id = p_request_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_employee_leave_balance(p_employee_id uuid, p_leave_type text, p_allocated_days numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller public.profiles%rowtype;
  target public.profiles%rowtype;
begin
  select * into caller from public.profiles
  where id = (select auth.uid()) and approval_status = 'approved' and role = 'hr';
  if caller.id is null then raise exception 'Only approved HR can manage leave balances'; end if;

  select * into target from public.profiles
  where id = p_employee_id and approval_status = 'approved'
    and role in ('employee', 'hr');
  if target.id is null then
    raise exception 'Leave balances can only be managed for approved Employee or HR accounts';
  end if;
  if p_leave_type is null or length(trim(p_leave_type)) = 0 then raise exception 'Leave type is required'; end if;
  if p_allocated_days is null or p_allocated_days < 0 then raise exception 'Allocated days cannot be negative'; end if;

  insert into public.leave_balances(employee_id, leave_type, allocated_days)
  values (p_employee_id, trim(p_leave_type), p_allocated_days)
  on conflict (employee_id, leave_type) do update
  set allocated_days = excluded.allocated_days, updated_at = now();
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_employee_details(p_user_id uuid, p_department text, p_designation text, p_phone text, p_joining_date date, p_manager_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_role text;
  caller_status text;
  manager_status text;
  would_create_cycle boolean := false;
begin
  select p.role, p.approval_status
    into caller_role, caller_status
  from public.profiles p
  where p.id = (select auth.uid());

  if caller_role is null
     or caller_status is distinct from 'approved'
     or caller_role not in ('hr', 'admin', 'super_admin') then
    raise exception 'Only approved HR/Admin accounts can edit employee details';
  end if;

  if p_user_id is null then
    raise exception 'Employee ID is required';
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'Employee profile not found';
  end if;

  if p_manager_id is not null then
    if p_manager_id = p_user_id then
      raise exception 'An employee cannot report to themselves';
    end if;

    select p.approval_status into manager_status
    from public.profiles p
    where p.id = p_manager_id;

if manager_status is distinct from 'approved' then
      raise exception 'The selected manager must have an approved profile';
    end if;

    -- Prevent loops such as A reports to B while B reports to A.
    with recursive descendants(id) as (
      select p.id
      from public.profiles p
      where p.manager_id = p_user_id
      union
      select child.id
      from public.profiles child
      join descendants d on child.manager_id = d.id
    )
    select exists (
      select 1 from descendants d where d.id = p_manager_id
    ) into would_create_cycle;

    if would_create_cycle then
      raise exception 'This manager assignment would create a reporting cycle';
    end if;
  end if;

  update public.profiles
  set department = nullif(trim(p_department), ''),
      designation = nullif(trim(p_designation), ''),
      phone = nullif(trim(p_phone), ''),
      joining_date = p_joining_date,
      manager_id = p_manager_id
  where id = p_user_id;
end;
$function$
;
create trigger leave_application_notification after insert on public.leave_requests for each row execute function public.notify_leave_application();
