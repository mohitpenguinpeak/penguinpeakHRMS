-- ISOLATED TEST DATABASE ONLY. Never run against your Supabase project.
-- Minimal structure and baseline policies from the supplied metadata export.
-- Helper function bodies are test stubs; production RPC source is still pending.
create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.profiles (id uuid not null, full_name text default ''::text not null, approval_status text default 'pending'::text not null, created_at timestamp with time zone default now() not null, role text default 'employee'::text not null, department text, designation text, phone text, joining_date date, manager_id uuid, profile_details jsonb default '{}'::jsonb not null, avatar_url text);
create table public.conversations (id uuid default gen_random_uuid() not null, title text, is_group boolean default false not null, created_at timestamp with time zone default now() not null);
create table public.conversation_participants (conversation_id uuid not null, user_id uuid not null, joined_at timestamp with time zone default now() not null);
create table public.messages (id uuid default gen_random_uuid() not null, conversation_id uuid not null, sender_id uuid not null, message text not null, created_at timestamp with time zone default now() not null);
create table public.holidays (id uuid default gen_random_uuid() not null, name text not null, holiday_date date not null, type text default 'National Holiday'::text not null, created_at timestamp with time zone default timezone('utc'::text, now()) not null);
create table public.push_tokens (token text not null, user_id uuid not null, updated_at timestamp with time zone default now() not null);
alter table public.conversation_participants add constraint conversation_participants_pkey PRIMARY KEY (conversation_id, user_id);
alter table public.conversations add constraint conversations_pkey PRIMARY KEY (id);
alter table public.holidays add constraint holidays_pkey PRIMARY KEY (id);
alter table public.messages add constraint messages_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'management'::text, 'employee'::text, 'hr'::text, 'super_admin'::text])));
alter table public.push_tokens add constraint push_tokens_pkey PRIMARY KEY (token);
alter table public.profiles enable row level security; grant all on public.profiles to authenticated, anon;
alter table public.conversations enable row level security; grant all on public.conversations to authenticated, anon;
alter table public.conversation_participants enable row level security; grant all on public.conversation_participants to authenticated, anon;
alter table public.messages enable row level security; grant all on public.messages to authenticated, anon;
alter table public.holidays enable row level security; grant all on public.holidays to authenticated, anon;
alter table public.push_tokens enable row level security; grant all on public.push_tokens to authenticated, anon;
create function public.is_approved_user() returns boolean language sql stable security definer as $$ select exists(select 1 from public.profiles where id=auth.uid() and approval_status='approved') $$;
create function public.is_hr_admin() returns boolean language sql stable security definer as $$ select exists(select 1 from public.profiles where id=auth.uid() and role in ('hr','admin','super_admin') and approval_status='approved') $$;
create function public.can_manage_employee_profiles() returns boolean language sql stable security definer as $$ select public.is_hr_admin() $$;
create policy "Users can insert participants" on public.conversation_participants for INSERT to authenticated with check (true);
create policy "Users can select participants" on public.conversation_participants for SELECT to authenticated using (true);
create policy "Users can insert conversations" on public.conversations for INSERT to authenticated with check (true);
create policy "Users can select conversations" on public.conversations for SELECT to authenticated using (true);
create policy "Admins and HR can manage holidays" on public.holidays for ALL to authenticated using (true) with check (true);
create policy "Authenticated users can view holidays" on public.holidays for SELECT to authenticated using (true);
create policy "Participants can insert messages" on public.messages for INSERT to authenticated with check (((sender_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM conversation_participants cp
  WHERE ((cp.conversation_id = messages.conversation_id) AND (cp.user_id = auth.uid()))))));
create policy "Participants can view messages" on public.messages for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM conversation_participants cp
  WHERE ((cp.conversation_id = messages.conversation_id) AND (cp.user_id = auth.uid())))));
create policy "Approved users can view approved employee profiles" on public.profiles for SELECT to authenticated using ((( SELECT is_approved_user() AS is_approved_user) AND (approval_status = 'approved'::text)));
create policy "Employees can view their own profile" on public.profiles for SELECT to authenticated using ((( SELECT auth.uid() AS uid) = id));
create policy "HR admins can update employee approval" on public.profiles for UPDATE to authenticated using (( SELECT is_hr_admin() AS is_hr_admin)) with check (( SELECT is_hr_admin() AS is_hr_admin));
create policy "HR admins can view employee profiles" on public.profiles for SELECT to authenticated using (( SELECT is_hr_admin() AS is_hr_admin));
create policy "profiles_update_by_owner_or_hr" on public.profiles for UPDATE to authenticated using (((auth.uid() = id) OR can_manage_employee_profiles())) with check (((auth.uid() = id) OR can_manage_employee_profiles()));
create policy "push_tokens_delete_own" on public.push_tokens for DELETE to authenticated using ((user_id = auth.uid()));
create policy "push_tokens_select_own" on public.push_tokens for SELECT to authenticated using ((user_id = auth.uid()));
alter table public.conversation_participants add constraint conversation_participants_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE;
alter table public.conversation_participants add constraint conversation_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.messages add constraint messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE;
alter table public.messages add constraint messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.push_tokens add constraint push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
-- Representative legacy wall policy with unconditional authenticated SELECT.
-- Lets stability tests prove the added restrictive approval boundary matters.
create table public.company_wall_posts (
  id uuid primary key default gen_random_uuid(), author_id uuid references public.profiles(id),
  post_type text default 'post', title text, content text not null,
  is_pinned boolean default false, created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.company_wall_posts enable row level security;
grant select, insert on public.company_wall_posts to authenticated;
create policy legacy_wall_read on public.company_wall_posts for select to authenticated using (true);
create policy legacy_wall_insert on public.company_wall_posts for insert to authenticated with check(author_id=auth.uid());
