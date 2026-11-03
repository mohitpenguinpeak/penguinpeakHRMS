-- Defense in depth: signed-in pending/rejected users cannot register delivery tokens.
-- Preserve existing tokens and role names. This does not replace profiles RLS review.
create or replace function public.register_push_token(p_token text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or p_token is null
     or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'Invalid push registration';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.approval_status = 'approved'
      and p.role in ('employee', 'management', 'admin', 'hr', 'super_admin')
  ) then
    raise exception 'Approved account required' using errcode = '42501';
  end if;
  insert into public.push_tokens(token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end;
$$;
revoke all on function public.register_push_token(text) from public, anon;
grant execute on function public.register_push_token(text) to authenticated;
