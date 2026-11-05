-- HR modules. Requires migrations 004–008. Apply once using the migration workflow.
begin;
create table public.hr_records (
  id uuid primary key default gen_random_uuid(),
  module text not null check (module in ('onboarding','payslip','expense','shift','swap','performance','asset','ticket','document','offboarding')),
  employee_id uuid references public.profiles(id) not null,
  created_by uuid references public.profiles(id) not null,
  title text not null check (length(trim(title)) between 1 and 160),
  description text not null default '' check (length(description) <= 8000),
  data jsonb not null default '{}' check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 32768),
  status text not null,
  company_wide boolean not null default false check (not company_wide or module = 'document'),
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index hr_records_employee on public.hr_records(employee_id, module, created_at desc);
create index hr_records_module on public.hr_records(module, created_at desc);
create unique index hr_active_asset_tag on public.hr_records(lower(data->>'asset_tag')) where module = 'asset' and status <> 'returned';
create unique index hr_monthly_payslip on public.hr_records(employee_id, (data->>'period')) where module = 'payslip';
create table public.hr_record_history (
  id bigint generated always as identity primary key,
  record_id uuid not null references public.hr_records(id),
  actor_id uuid not null references public.profiles(id),
  action text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);
create index hr_history_record on public.hr_record_history(record_id, created_at);
create table public.hr_acknowledgements (
  record_id uuid not null references public.hr_records(id),
  employee_id uuid not null references public.profiles(id),
  acknowledged_at timestamptz not null default now(),
  primary key(record_id, employee_id)
);
create table public.hr_attachments (
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.hr_records(id),
  uploaded_by uuid not null references public.profiles(id),
  name text not null check (length(name) between 1 and 240),
  path text not null unique,
  created_at timestamptz not null default now()
);

create function public.hr_is_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and exists(select 1 from public.profiles where id = auth.uid() and role in ('hr','admin','super_admin'));
$$;
create function public.hr_is_manager(subject uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and subject <> auth.uid() and exists(select 1 from public.profiles where id = subject and manager_id = auth.uid());
$$;
create function public.hr_can_read(record public.hr_records) returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and (
    public.hr_is_staff() or record.module = 'shift' or
    (record.employee_id = auth.uid() and (record.module not in ('payslip','document') or record.status = 'published')) or
    (record.company_wide and record.status = 'published') or
    (record.module in ('expense','performance') and public.hr_is_manager(record.employee_id))
  );
$$;
alter table public.hr_records enable row level security;
alter table public.hr_record_history enable row level security;
alter table public.hr_acknowledgements enable row level security;
alter table public.hr_attachments enable row level security;
revoke all on public.hr_records, public.hr_record_history, public.hr_acknowledgements, public.hr_attachments from public, anon, authenticated;
grant select on public.hr_records, public.hr_record_history, public.hr_acknowledgements, public.hr_attachments to authenticated;
create policy hr_read on public.hr_records for select to authenticated using(public.hr_can_read(hr_records));
create policy hr_history_read on public.hr_record_history for select to authenticated using(exists(select 1 from public.hr_records r where r.id = record_id));
create policy hr_ack_read on public.hr_acknowledgements for select to authenticated using((employee_id = auth.uid() or public.hr_is_staff()) and exists(select 1 from public.hr_records r where r.id = record_id));
create policy hr_attachment_read on public.hr_attachments for select to authenticated using(exists(select 1 from public.hr_records r where r.id = record_id));

create function public.hr_create_record(p_module text, p_employee uuid, p_title text, p_description text, p_data jsonb, p_company_wide boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare subject uuid := coalesce(p_employee, auth.uid()); staff boolean := public.hr_is_staff(); record_id uuid; state text; required_keys text[]; k text; numeric_value numeric;
begin
  if not public.has_approved_account() then raise exception 'Approved account required' using errcode='42501'; end if;
  if p_module not in ('onboarding','payslip','expense','shift','swap','performance','asset','ticket','document','offboarding') then raise exception 'Unknown module'; end if;
  if not staff and (subject <> auth.uid() or p_module in ('onboarding','payslip','shift','asset','document') or p_company_wide) then raise exception 'HR access required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles where id = subject and approval_status = 'approved') then raise exception 'Select an approved employee'; end if;
  if jsonb_typeof(p_data) <> 'object' or p_data is null then raise exception 'Invalid details'; end if;
  if (p_data - array['joining_date','buddy','period','basic','allowances','deductions','amount','expense_date','category','start_date','start_time','end_time','weekly_off','shift_id','target_employee','target_shift_id','goals','self_review','asset_tag','serial','condition','return_due','priority','version','last_day']) <> '{}'::jsonb then raise exception 'Unsupported details'; end if;
  required_keys := case p_module
    when 'onboarding' then array['joining_date','buddy'] when 'payslip' then array['period','basic','allowances','deductions']
    when 'expense' then array['amount','expense_date','category'] when 'shift' then array['start_date','start_time','end_time','weekly_off']
    when 'swap' then array['shift_id','target_employee','target_shift_id'] when 'performance' then array['period','goals']
    when 'asset' then array['asset_tag','serial','condition','return_due'] when 'ticket' then array['category','priority']
    when 'document' then array['category','version'] else array['last_day'] end;
  foreach k in array required_keys loop
    if length(trim(coalesce(p_data->>k,''))) = 0 then raise exception 'Missing field: %', k; end if;
  end loop;
  for k in select jsonb_object_keys(p_data) loop
    if jsonb_typeof(p_data->k) <> 'string' or length(p_data->>k) > 4000 then raise exception 'Invalid field: %', k; end if;
    if k in ('basic','allowances','deductions','amount') then
      if (p_data->>k) !~ '^\d+(\.\d{1,2})?$' then raise exception 'Invalid amount'; end if;
      numeric_value := (p_data->>k)::numeric;
      if numeric_value < 0 or numeric_value > 100000000 or (k='amount' and numeric_value=0) then raise exception 'Invalid amount'; end if;
    end if;
    if k in ('joining_date','expense_date','start_date','return_due','last_day') then
      if to_char((p_data->>k)::date,'YYYY-MM-DD') <> p_data->>k then raise exception 'Invalid date'; end if;
    end if;
    if k in ('start_time','end_time') and (p_data->>k) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid shift time'; end if;
  end loop;
  if p_module='payslip' and ((p_data->>'period') !~ '^\d{4}-(0[1-9]|1[0-2])$' or (p_data->>'deductions')::numeric > (p_data->>'basic')::numeric + (p_data->>'allowances')::numeric) then raise exception 'Invalid salary month or deductions'; end if;
  if p_module='swap' then
    if not exists(select 1 from public.hr_records where id=(p_data->>'shift_id')::uuid and module='shift' and employee_id=subject and status='assigned') or
       not exists(select 1 from public.hr_records where id=(p_data->>'target_shift_id')::uuid and module='shift' and employee_id=(p_data->>'target_employee')::uuid and employee_id<>subject and status='assigned') then raise exception 'Both shifts must be assigned to the specified employees'; end if;
  end if;
  state := case p_module when 'onboarding' then 'active' when 'payslip' then 'draft' when 'document' then 'draft' when 'performance' then 'draft' when 'shift' then 'assigned' when 'asset' then 'assigned' when 'ticket' then 'open' else 'submitted' end;
  insert into public.hr_records(module,employee_id,created_by,title,description,data,status,company_wide)
    values(p_module,subject,auth.uid(),trim(p_title),coalesce(p_description,''),p_data,state,p_company_wide) returning id into record_id;
  insert into public.hr_record_history(record_id,actor_id,action) values(record_id,auth.uid(),'created');
  return record_id;
end;
$$;

create function public.hr_update_record(p_id uuid, p_revision integer, p_action text, p_note text default '', p_patch jsonb default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare r public.hr_records; staff boolean := public.hr_is_staff(); owner boolean; manager boolean; allowed boolean := false; needed integer; a public.hr_records; b public.hr_records; checks jsonb;
begin
  select * into r from public.hr_records where id=p_id for update;
  if not found or not public.hr_can_read(r) then raise exception 'Record unavailable' using errcode='42501'; end if;
  if r.revision <> p_revision then raise exception 'Record changed. Refresh and try again.' using errcode='40001'; end if;
  if length(p_note)>4000 or jsonb_typeof(p_patch)<>'object' or p_patch is null then raise exception 'Invalid update'; end if;
  owner := r.employee_id = auth.uid(); manager := public.hr_is_manager(r.employee_id);
  if p_action='save' then
    allowed := (r.module='performance' and r.status='draft' and owner and p_patch - 'self_review' = '{}'::jsonb and jsonb_typeof(p_patch->'self_review')='string' and length(p_patch->>'self_review')<=4000) or
      (r.module='onboarding' and r.status='active' and (owner or staff)) or (r.module='offboarding' and r.status='approved' and staff);
    if r.module in ('onboarding','offboarding') then
      checks := p_patch->'checklist'; needed := 4;
      if p_patch - 'checklist' <> '{}'::jsonb or jsonb_typeof(checks) <> 'array' or jsonb_array_length(checks) <> needed or exists(select 1 from jsonb_array_elements(checks) x where jsonb_typeof(x)<>'boolean') or checks is null then allowed := false; end if;
    end if;
  else
    if p_patch <> '{}'::jsonb then raise exception 'Use progress save for detail updates'; end if;
    allowed := case r.module
      when 'onboarding' then r.status='active' and p_action='completed' and (staff or owner) and r.data->'checklist'='[true,true,true,true]'::jsonb
      when 'payslip' then r.status='draft' and p_action='published' and staff and exists(select 1 from public.hr_attachments where record_id=r.id)
      when 'document' then r.status='draft' and p_action='published' and staff and exists(select 1 from public.hr_attachments where record_id=r.id)
      when 'expense' then not owner and ((r.status='submitted' and p_action='manager_approved' and (manager or (staff and not exists(select 1 from public.profiles where id=r.employee_id and manager_id is not null))) and exists(select 1 from public.hr_attachments where record_id=r.id)) or (r.status='manager_approved' and p_action='approved' and staff) or (r.status='approved' and p_action='paid' and staff) or (r.status in ('submitted','manager_approved') and p_action='rejected' and (staff or manager)))
      when 'shift' then staff and r.status='assigned' and p_action in ('completed','cancelled')
      when 'swap' then staff and not owner and r.status='submitted' and p_action in ('approved','rejected')
      when 'performance' then (r.status='draft' and p_action='submitted' and owner and length(trim(coalesce(r.data->>'self_review','')))>0) or (r.status='submitted' and p_action='reviewed' and not owner and (staff or manager))
      when 'asset' then (r.status='assigned' and p_action='return_requested' and owner) or (r.status in ('assigned','return_requested') and p_action='returned' and staff)
      when 'ticket' then (staff and ((r.status='open' and p_action='in_progress') or (r.status in ('open','in_progress') and p_action='resolved'))) or ((staff or owner) and r.status='resolved' and p_action='closed') or (owner and r.status='resolved' and p_action='open')
      when 'offboarding' then (staff and not owner and r.status='submitted' and p_action in ('approved','rejected')) or (staff and r.status='approved' and p_action='completed' and r.data->'checklist'='[true,true,true,true]'::jsonb)
      else false end;
  end if;
  if not coalesce(allowed,false) then raise exception 'Action not allowed, or required progress/attachment is missing' using errcode='42501'; end if;
  if p_action in ('manager_approved','rejected','paid','reviewed','returned','resolved','approved') and length(trim(p_note))=0 then raise exception 'A decision note is required'; end if;
  if r.module='swap' and p_action='approved' then
    -- Deterministic lock order avoids deadlocks between competing swaps.
    perform 1 from public.hr_records where id in ((r.data->>'shift_id')::uuid,(r.data->>'target_shift_id')::uuid) order by id for update;
    select * into a from public.hr_records where id=(r.data->>'shift_id')::uuid;
    select * into b from public.hr_records where id=(r.data->>'target_shift_id')::uuid;
    if a.employee_id<>r.employee_id or b.employee_id<>(r.data->>'target_employee')::uuid or a.status<>'assigned' or b.status<>'assigned' then raise exception 'Shift assignments changed. Submit a new swap.'; end if;
    update public.hr_records set employee_id=case when id=a.id then b.employee_id else a.employee_id end, revision=revision+1, updated_at=now() where id in (a.id,b.id);
    insert into public.hr_record_history(record_id,actor_id,action,note) values(a.id,auth.uid(),'swapped',p_note),(b.id,auth.uid(),'swapped',p_note);
  end if;
  update public.hr_records set status=case when p_action='save' then status else p_action end, data=data || p_patch, revision=revision+1, updated_at=now() where id=r.id;
  insert into public.hr_record_history(record_id,actor_id,action,note) values(r.id,auth.uid(),p_action,p_note);
end;
$$;

create function public.hr_acknowledge(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.hr_records;
begin
  select * into r from public.hr_records where id=p_id;
  if not found or not public.hr_can_read(r) or r.module<>'document' or r.status<>'published' then raise exception 'Document unavailable' using errcode='42501'; end if;
  insert into public.hr_acknowledgements(record_id,employee_id) values(p_id,auth.uid()) on conflict do nothing;
end;
$$;

create function public.hr_can_attach(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and exists(select 1 from public.hr_records r where r.id=p_id and (
    (public.hr_is_staff() and ((r.module in ('document','payslip') and r.status='draft') or (r.module='onboarding' and r.status='active') or (r.module='ticket' and r.status in ('open','in_progress')) or (r.module='offboarding' and r.status in ('submitted','approved')))) or
    (r.employee_id=auth.uid() and ((r.module='expense' and r.status='submitted') or (r.module='ticket' and r.status in ('open','in_progress')) or (r.module='onboarding' and r.status='active') or (r.module='offboarding' and r.status='submitted')))
  ));
$$;
create function public.hr_register_attachment(p_id uuid, p_name text, p_path text) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.hr_records where id=p_id for update;
  if not public.hr_can_attach(p_id) or split_part(p_path,'/',1)<>p_id::text or split_part(p_path,'/',2)<>auth.uid()::text then raise exception 'Attachment access denied' using errcode='42501'; end if;
  if not exists(select 1 from storage.objects where bucket_id='hr-private' and name=p_path) then raise exception 'Upload the file first'; end if;
  insert into public.hr_attachments(record_id,uploaded_by,name,path) values(p_id,auth.uid(),p_name,p_path);
  insert into public.hr_record_history(record_id,actor_id,action,note) values(p_id,auth.uid(),'attachment_added',p_name);
end;
$$;
-- No public bucket or public URLs. Only authorized records grant file access.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('hr-private','hr-private',false,10485760,array['application/pdf','image/jpeg','image/png']) on conflict (id) do nothing;
create policy hr_files_read on storage.objects for select to authenticated using(bucket_id='hr-private' and exists(select 1 from public.hr_attachments a join public.hr_records r on r.id=a.record_id where a.path=storage.objects.name and public.hr_can_read(r)));
create policy hr_files_upload on storage.objects for insert to authenticated with check(bucket_id='hr-private' and public.has_approved_account() and split_part(name,'/',2)=auth.uid()::text and public.hr_can_attach(split_part(name,'/',1)::uuid));
-- Upload cleanup is allowed only before an attachment is registered.
create policy hr_files_cleanup on storage.objects for delete to authenticated using(bucket_id='hr-private' and split_part(name,'/',2)=auth.uid()::text and public.has_approved_account() and not exists(select 1 from public.hr_attachments a where a.path=storage.objects.name));

revoke all on function public.hr_is_staff(), public.hr_is_manager(uuid), public.hr_can_read(public.hr_records), public.hr_can_attach(uuid), public.hr_create_record(text,uuid,text,text,jsonb,boolean), public.hr_update_record(uuid,integer,text,text,jsonb), public.hr_acknowledge(uuid), public.hr_register_attachment(uuid,text,text) from public, anon;
grant execute on function public.hr_is_staff(), public.hr_is_manager(uuid), public.hr_can_read(public.hr_records), public.hr_can_attach(uuid), public.hr_create_record(text,uuid,text,text,jsonb,boolean), public.hr_update_record(uuid,integer,text,text,jsonb), public.hr_acknowledge(uuid), public.hr_register_attachment(uuid,text,text) to authenticated;
commit;
