create table public.push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;
grant select, delete on public.push_tokens to authenticated;
create policy push_tokens_select_own on public.push_tokens for select
  to authenticated using (user_id = auth.uid());
create policy push_tokens_delete_own on public.push_tokens for delete
  to authenticated using (user_id = auth.uid());
-- An installation may change account. Do not expose another account's tokens.
create function public.register_push_token(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'Invalid push registration';
  end if;
  insert into public.push_tokens(token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end;
$$;
revoke all on function public.register_push_token(text) from public;
grant execute on function public.register_push_token(text) to authenticated;
