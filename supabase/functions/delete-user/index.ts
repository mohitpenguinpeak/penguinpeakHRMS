import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (body: object, status = 200) => Response.json(body, { status, headers });

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  try {
    const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return reply({ error: 'Sign in required' }, 401);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: identity, error: identityError } = await db.auth.getUser(token);
    if (identityError || !identity.user) return reply({ error: 'Invalid session' }, 401);
    const { data: caller, error: callerError } = await db.from('profiles').select('role, approval_status').eq('id', identity.user.id).single();
    if (callerError || caller?.role !== 'hr' || caller.approval_status !== 'approved') return reply({ error: 'Only approved HR can delete users' }, 403);
    const { user_id: userId } = await request.json();
    if (typeof userId !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(userId)) return reply({ error: 'Invalid user ID' }, 400);
    if (userId === identity.user.id) return reply({ error: 'You cannot delete your own account' }, 403);
    const { data: reports, error: reportsError } = await db.from('profiles').select('id').eq('manager_id', userId).eq('approval_status', 'approved').limit(1);
    if (reportsError) throw reportsError;
    if (reports?.length) return reply({ error: 'Reassign this user’s direct reports before deleting them' }, 409);

    // Storage must be removed via its API, never by deleting storage metadata.
    // Read bounded batches repeatedly: successful removal advances the result set.
    while (true) {
      const { data: objects, error } = await db.schema('public').rpc('user_owned_storage_objects', { p_user_id: userId });
      if (error) throw error;
      if (!objects?.length) break;
      const buckets = new Map<string, string[]>();
      for (const object of objects) {
        const paths = buckets.get(object.bucket_id) ?? [];
        paths.push(object.name);
        buckets.set(object.bucket_id, paths);
      }
      for (const [bucket, paths] of buckets) {
        const { error: removeError } = await db.storage.from(bucket).remove(paths);
        if (removeError) throw removeError;
      }
    }
    // Hard deletion: auth identities and sessions disappear; public FKs clean up
    // owned records in the same database transaction as auth deletion.
    const { error: deleteError } = await db.auth.admin.deleteUser(userId, false);
    if (deleteError) throw deleteError;
    return reply({ deleted: true, user_id: userId });
  } catch (error) {
    console.error('User deletion failed', error instanceof Error ? error.message : 'Unknown error');
    return reply({ error: 'Could not permanently delete user. Check the deletion migration and function logs, then retry.' }, 500);
  }
});
