-- READ ONLY: one result row containing all schema/security metadata.
-- Run in the correct Supabase project's SQL editor as an administrator.
-- Export the audit JSON result; it contains no employee rows or token values.
-- Internal metadata still belongs in private project storage.
-- Trigger arguments/definitions are intentionally excluded: webhooks can contain secrets.
select jsonb_build_object(
  'capture', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select current_database() as database_name, current_user as audit_role,
             now() as captured_at
    ) audit_rows),
  'columns', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select table_schema, table_name, column_name, data_type, is_nullable, column_default
      from information_schema.columns
      where table_schema = 'public'
      order by table_name, ordinal_position
    ) audit_rows),
  'table_security', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select n.nspname as schema_name, c.relname as table_name,
             c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p')
      order by c.relname
    ) audit_rows),
  'policies', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      from pg_policies where schemaname in ('public', 'storage')
      order by schemaname, tablename, policyname
    ) audit_rows),
  'table_grants', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select table_schema, table_name, grantee, privilege_type
      from information_schema.table_privileges
      where table_schema in ('public', 'storage') and grantee in ('anon', 'authenticated')
      order by table_schema, table_name, grantee, privilege_type
    ) audit_rows),
  'column_grants', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select table_schema, table_name, column_name, grantee, privilege_type
      from information_schema.column_privileges
      where table_schema = 'public' and grantee in ('anon', 'authenticated')
      order by table_name, column_name, grantee
    ) audit_rows),
  'functions', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select n.nspname as schema_name, p.proname as function_name,
             pg_get_function_identity_arguments(p.oid) as arguments,
             pg_get_function_result(p.oid) as result,
             p.prosecdef as security_definer, p.proconfig as configuration,
             has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
             has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' order by p.proname
    ) audit_rows),
  'constraints', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select conrelid::regclass as table_name, conname, contype,
             pg_get_constraintdef(oid) as constraint_definition
      from pg_constraint
      where connamespace = 'public'::regnamespace order by conrelid::regclass::text, conname
    ) audit_rows),
  'indexes', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select schemaname, tablename, indexname, indexdef
      from pg_indexes where schemaname = 'public' order by tablename, indexname
    ) audit_rows),
  'triggers', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select n.nspname as schema_name, c.relname as table_name, t.tgname as trigger_name,
             p.proname as function_name, t.tgenabled as enabled
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = t.tgfoid
      where n.nspname = 'public' and not t.tgisinternal
      order by c.relname, t.tgname
    ) audit_rows),
  'realtime_tables', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select schemaname, tablename from pg_publication_tables
      where pubname = 'supabase_realtime' order by schemaname, tablename
    ) audit_rows),
  'storage_buckets', (select coalesce(jsonb_agg(to_jsonb(audit_rows)), '[]'::jsonb)
    from (
      select id, name, public, file_size_limit, allowed_mime_types
      from storage.buckets order by name
    ) audit_rows)
) as audit;
