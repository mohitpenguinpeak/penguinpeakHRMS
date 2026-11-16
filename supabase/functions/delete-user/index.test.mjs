import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const actor = '11111111-1111-1111-1111-111111111111';
const target = '22222222-2222-2222-2222-222222222222';
const source = stripTypeScriptTypes(readFileSync(new URL('./index.ts', import.meta.url), 'utf8').replace(/^import .*;\n/, ''));
function setup({ role = 'hr', reports = [], storage = false, storageError = false } = {}) {
  const calls = [];
  let storageRead = false;
  let handler;
  const db = {
    auth: { getUser: async () => ({ data: { user: { id: actor } } }), admin: {
      deleteUser: async (...args) => { calls.push(['delete', ...args]); return {}; },
    } },
    from: () => ({ select() { return this; }, eq() { return this; },
      single: async () => ({ data: { role, approval_status: 'approved' } }),
      limit: async () => ({ data: reports }),
    }),
    schema: () => ({ rpc: async () => {
      const rows = storage && !storageRead ? [{ bucket_id: 'private', name: 'file.pdf' }] : [];
      storageRead = true;
      return { data: rows };
    } }),
    storage: { from: (bucket) => ({ remove: async (paths) => {
      calls.push(['storage', bucket, ...paths]);
      return storageError ? { error: new Error('storage unavailable') } : {};
    } }) },
  };
  const context = vm.createContext({ Request, Response, console: { error() {} },
    createClient: () => db, Deno: { env: { get: () => 'test' }, serve: (fn) => { handler = fn; } },
  });
  new vm.Script(source).runInContext(context);
  return { calls, request: (id = target, authenticated = true) => handler(new Request('https://local/delete-user', {
    method: 'POST', headers: authenticated ? { Authorization: 'Bearer token', 'Content-Type': 'application/json' } : {},
    body: JSON.stringify({ user_id: id }),
  })) };
}
test('unauthenticated and non-HR requests cannot delete', async () => {
  const missing = setup(); assert.equal((await missing.request(target, false)).status, 401); assert.equal(missing.calls.length, 0);
  const employee = setup({ role: 'employee' }); assert.equal((await employee.request()).status, 403); assert.equal(employee.calls.length, 0);
});
test('self deletion and managers with direct reports are blocked', async () => {
  const self = setup(); assert.equal((await self.request(actor)).status, 403); assert.equal(self.calls.length, 0);
  const manager = setup({ reports: [{ id: 'report' }] }); assert.equal((await manager.request()).status, 409); assert.equal(manager.calls.length, 0);
});
test('storage is deleted before hard Auth deletion', async () => {
  const api = setup({ storage: true });
  const response = await api.request(); assert.equal(response.status, 200);
  assert.equal((await response.json()).deleted, true);
  assert.deepEqual(api.calls, [['storage', 'private', 'file.pdf'], ['delete', target, false]]);
});
test('storage failure never reports successful Auth deletion', async () => {
  const api = setup({ storage: true, storageError: true });
  assert.equal((await api.request()).status, 500);
  assert.equal(api.calls.some((call) => call[0] === 'delete'), false);
});
