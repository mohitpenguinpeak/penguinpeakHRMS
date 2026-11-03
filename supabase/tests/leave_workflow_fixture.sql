-- ISOLATED TEST DATABASE ONLY. Exported structure; synthetic rows supplied by tests.
create table public.leave_balances (id uuid default gen_random_uuid() not null, employee_id uuid not null, leave_type text not null, allocated_days numeric default 0 not null, used_days numeric default 0 not null, updated_at timestamp with time zone default now() not null);
create table public.leave_requests (id uuid default gen_random_uuid() not null, employee_id uuid not null, manager_id uuid not null, leave_type text not null, start_date date not null, end_date date not null, days numeric not null, reason text not null, manager_status text default 'pending'::text not null, manager_comment text, hr_status text default 'pending'::text not null, hr_comment text, created_at timestamp with time zone default now() not null, reviewed_by_manager_at timestamp with time zone, reviewed_by_hr_at timestamp with time zone);
create table public.notifications (id uuid default gen_random_uuid() not null, recipient_id uuid not null, leave_request_id text not null, title text not null, body text not null, created_at timestamp with time zone default now() not null, read_at timestamp with time zone, dismissed_at timestamp with time zone);
alter table public.leave_balances add constraint leave_balances_pkey PRIMARY KEY (id);
alter table public.leave_requests add constraint leave_requests_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.leave_balances add constraint leave_balances_employee_type_unique UNIQUE (employee_id, leave_type);
alter table public.notifications add constraint notifications_recipient_id_leave_request_id_key UNIQUE (recipient_id, leave_request_id);
alter table public.leave_balances add constraint leave_balances_allocated_days_check CHECK ((allocated_days >= (0)::numeric));
alter table public.leave_balances add constraint leave_balances_leave_type_check CHECK ((length(TRIM(BOTH FROM leave_type)) > 0));
alter table public.leave_balances add constraint leave_balances_used_days_check CHECK ((used_days >= (0)::numeric));
alter table public.leave_balances add constraint leave_balances_used_not_over_allocated CHECK ((used_days <= allocated_days));
alter table public.leave_requests add constraint leave_dates_valid CHECK ((end_date >= start_date));
alter table public.leave_requests add constraint leave_requests_days_check CHECK ((days > (0)::numeric));
alter table public.leave_requests add constraint leave_requests_hr_status_check CHECK ((hr_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.leave_requests add constraint leave_requests_leave_type_check CHECK ((length(TRIM(BOTH FROM leave_type)) > 0));
alter table public.leave_requests add constraint leave_requests_manager_status_check CHECK ((manager_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.leave_requests add constraint leave_requests_reason_check CHECK ((length(TRIM(BOTH FROM reason)) > 0));
alter table public.leave_balances add constraint leave_balances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.leave_requests add constraint leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.leave_requests add constraint leave_requests_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES profiles(id);
alter table public.notifications add constraint notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.leave_balances enable row level security; grant select on public.leave_balances to authenticated;
alter table public.leave_requests enable row level security; grant select on public.leave_requests to authenticated;
alter table public.notifications enable row level security; grant select on public.notifications to authenticated;
create policy "HR can read employee and HR leave balances" on public.leave_balances for SELECT to authenticated using (((EXISTS ( SELECT 1
   FROM profiles caller
  WHERE ((caller.id = ( SELECT auth.uid() AS uid)) AND (caller.approval_status = 'approved'::text) AND (caller.role = 'hr'::text)))) AND (EXISTS ( SELECT 1
   FROM profiles target
  WHERE ((target.id = leave_balances.employee_id) AND (target.role = ANY (ARRAY['employee'::text, 'hr'::text])))))));
create policy "Users can read own leave balance" on public.leave_balances for SELECT to authenticated using ((employee_id = ( SELECT auth.uid() AS uid)));
create policy "Users managers and HR can read relevant leave requests" on public.leave_requests for SELECT to authenticated using (((employee_id = ( SELECT auth.uid() AS uid)) OR (manager_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM profiles caller
  WHERE ((caller.id = ( SELECT auth.uid() AS uid)) AND (caller.approval_status = 'approved'::text) AND (caller.role = 'hr'::text))))));
create policy "notifications_read_own" on public.notifications for SELECT to authenticated using ((recipient_id = auth.uid()));
create policy "notifications_update_own" on public.notifications for UPDATE to authenticated using ((recipient_id = auth.uid())) with check ((recipient_id = auth.uid()));
