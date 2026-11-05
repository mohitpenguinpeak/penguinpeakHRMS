-- Keep only the four selected HR services. Existing records/files are preserved.
-- Requires 202611040001_hr_modules.sql; apply once.
begin;
alter table public.hr_records add constraint hr_enabled_modules check (module in ('onboarding','payslip','ticket','document')) not valid;

create or replace function public.hr_can_read(record public.hr_records) returns boolean language sql stable security definer set search_path = '' as $$
  select record.module in ('onboarding','payslip','ticket','document') and public.has_approved_account() and (
    public.hr_is_staff() or
    (record.employee_id = auth.uid() and (record.module not in ('payslip','document') or record.status = 'published')) or
    (record.company_wide and record.status = 'published')
  );
$$;

create or replace function public.hr_create_record(p_module text, p_employee uuid, p_title text, p_description text, p_data jsonb, p_company_wide boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare subject uuid := coalesce(p_employee, auth.uid()); staff boolean := public.hr_is_staff(); record_id uuid; state text; required_keys text[]; k text; numeric_value numeric;
begin
  if not public.has_approved_account() then raise exception 'Approved account required' using errcode='42501'; end if;
  if p_module not in ('onboarding','payslip','ticket','document') then raise exception 'Unknown module'; end if;
  if not staff and (subject <> auth.uid() or p_module in ('onboarding','payslip','document') or p_company_wide) then raise exception 'HR access required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles where id = subject and approval_status = 'approved') then raise exception 'Select an approved employee'; end if;
  if jsonb_typeof(p_data) <> 'object' or p_data is null then raise exception 'Invalid details'; end if;
  if (p_data - array['joining_date','buddy','period','basic','allowances','deductions','category','priority','version']) <> '{}'::jsonb then raise exception 'Unsupported details'; end if;
  required_keys := case p_module when 'onboarding' then array['joining_date','buddy'] when 'payslip' then array['period','basic','allowances','deductions'] when 'ticket' then array['category','priority'] else array['category','version'] end;
  foreach k in array required_keys loop
    if length(trim(coalesce(p_data->>k,''))) = 0 then raise exception 'Missing field: %', k; end if;
  end loop;
  for k in select jsonb_object_keys(p_data) loop
    if jsonb_typeof(p_data->k) <> 'string' or length(p_data->>k) > 4000 then raise exception 'Invalid field: %', k; end if;
    if k in ('basic','allowances','deductions') then
      if (p_data->>k) !~ '^\d+(\.\d{1,2})?$' then raise exception 'Invalid amount'; end if;
      numeric_value := (p_data->>k)::numeric;
      if numeric_value < 0 or numeric_value > 100000000 then raise exception 'Invalid amount'; end if;
    end if;
    if k in ('joining_date') then
      if to_char((p_data->>k)::date,'YYYY-MM-DD') <> p_data->>k then raise exception 'Invalid date'; end if;
    end if;
  end loop;
  if p_module='payslip' and ((p_data->>'period') !~ '^\d{4}-(0[1-9]|1[0-2])$' or (p_data->>'deductions')::numeric > (p_data->>'basic')::numeric + (p_data->>'allowances')::numeric) then raise exception 'Invalid salary month or deductions'; end if;
  state := case p_module when 'onboarding' then 'active' when 'ticket' then 'open' else 'draft' end;
  insert into public.hr_records(module,employee_id,created_by,title,description,data,status,company_wide)
    values(p_module,subject,auth.uid(),trim(p_title),coalesce(p_description,''),p_data,state,p_company_wide) returning id into record_id;
  insert into public.hr_record_history(record_id,actor_id,action) values(record_id,auth.uid(),'created');
  return record_id;
end;
$$;

create or replace function public.hr_update_record(p_id uuid, p_revision integer, p_action text, p_note text default '', p_patch jsonb default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare r public.hr_records; staff boolean := public.hr_is_staff(); owner boolean; allowed boolean := false; needed integer; checks jsonb;
begin
  select * into r from public.hr_records where id=p_id for update;
  if not found or not public.hr_can_read(r) then raise exception 'Record unavailable' using errcode='42501'; end if;
  if r.revision <> p_revision then raise exception 'Record changed. Refresh and try again.' using errcode='40001'; end if;
  if length(p_note)>4000 or jsonb_typeof(p_patch)<>'object' or p_patch is null then raise exception 'Invalid update'; end if;
  owner := r.employee_id = auth.uid();
  if p_action='save' then
    allowed := r.module='onboarding' and r.status='active' and (owner or staff);
    if r.module='onboarding' then
      checks := p_patch->'checklist'; needed := 4;
      if p_patch - 'checklist' <> '{}'::jsonb or jsonb_typeof(checks) <> 'array' or jsonb_array_length(checks) <> needed or exists(select 1 from jsonb_array_elements(checks) x where jsonb_typeof(x)<>'boolean') or checks is null then allowed := false; end if;
    end if;
  else
    if p_patch <> '{}'::jsonb then raise exception 'Use progress save for detail updates'; end if;
    allowed := case r.module
      when 'onboarding' then r.status='active' and p_action='completed' and (staff or owner) and r.data->'checklist'='[true,true,true,true]'::jsonb
      when 'payslip' then r.status='draft' and p_action='published' and staff and exists(select 1 from public.hr_attachments where record_id=r.id)
      when 'document' then r.status='draft' and p_action='published' and staff and exists(select 1 from public.hr_attachments where record_id=r.id)
      when 'ticket' then (staff and ((r.status='open' and p_action='in_progress') or (r.status in ('open','in_progress') and p_action='resolved'))) or ((staff or owner) and r.status='resolved' and p_action='closed') or (owner and r.status='resolved' and p_action='open')
      else false end;
  end if;
  if not coalesce(allowed,false) then raise exception 'Action not allowed, or required progress/attachment is missing' using errcode='42501'; end if;
  if p_action='resolved' and length(trim(p_note))=0 then raise exception 'A resolution note is required'; end if;
  update public.hr_records set status=case when p_action='save' then status else p_action end, data=data || p_patch, revision=revision+1, updated_at=now() where id=r.id;
  insert into public.hr_record_history(record_id,actor_id,action,note) values(r.id,auth.uid(),p_action,p_note);
end;
$$;

create or replace function public.hr_can_attach(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and exists(select 1 from public.hr_records r where r.id=p_id and (
    (public.hr_is_staff() and r.module in ('document','payslip') and r.status='draft') or
    ((public.hr_is_staff() or r.employee_id=auth.uid()) and ((r.module='onboarding' and r.status='active') or (r.module='ticket' and r.status in ('open','in_progress'))))
  ));
$$;
-- Cleanup must check registered files outside RLS: retired records are hidden
-- from the caller, but their registered files must still remain protected.
create function public.hr_can_remove_upload(p_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and not exists (
    select 1 from public.hr_attachments a where a.path=p_path
  );
$$;
revoke all on function public.hr_can_remove_upload(text) from public, anon;
grant execute on function public.hr_can_remove_upload(text) to authenticated;
-- PostgreSQL DELETE also needs SELECT visibility for the orphan being cleaned.
create policy hr_upload_owner_read on storage.objects for select to authenticated using (
  bucket_id='hr-private' and split_part(name,'/',2)=auth.uid()::text
  and public.hr_can_remove_upload(name)
);
alter policy hr_files_cleanup on storage.objects using (
  bucket_id='hr-private' and split_part(name,'/',2)=auth.uid()::text
  and public.hr_can_remove_upload(name)
);
drop function public.hr_is_manager(uuid);
commit;
