// Executes actual transpiled handler with mocked Supabase, Google auth and HTTP.
// No live credentials/network/device messages. Pass a TypeScript library path.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const ts = require(process.argv[2] || 'typescript');
const source = readFileSync(new URL('../supabase/functions/send-leave-push/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*;\s*$/gm, '');
const compiled = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None },
  reportDiagnostics: true,
});
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
let handler;
let config;
let fetches;
let removed;
let logs;
const env = new Map();
const context = vm.createContext({
  Response,
  console: { info: (...args) => logs.push(args), error: (...args) => logs.push(args) },
  Deno: { env: { get: key => env.get(key) }, serve: fn => { handler = fn; } },
  GoogleAuth: class { async getAccessToken() { return 'synthetic-access'; } },
  createClient: () => ({ from(table) {
    return {
      select() { return this; },
      delete() { this.deleting = true; return this; },
      eq() {
        if (table === 'push_tokens') {
          if (this.deleting) { removed++; return Promise.resolve({ error: null }); }
          return Promise.resolve({ data: config.devices, error: null });
        }
        return this;
      },
      async single() {
        if (table === 'profiles') return { data: { approval_status: config.approval }, error: null };
        return { data: { id: 'notice', recipient_id: 'recipient', title: 'Leave', body: 'Review leave' }, error: null };
      },
    };
  } }),
  fetch: async (_url, options) => {
    fetches.push(JSON.parse(options.body));
    return Response.json(config.providerBody, { status: config.providerStatus });
  },
});
vm.runInContext(compiled.outputText, context);
function reset() {
  fetches = []; removed = 0; logs = [];
  env.clear();
  env.set('PUSH_WEBHOOK_SECRET', 'synthetic-webhook-secret');
  env.set('FCM_SERVICE_ACCOUNT_JSON', JSON.stringify({ project_id: 'test-project' }));
  config = { approval: 'approved', devices: [{ token: 'synthetic-device-token' }], providerStatus: 200, providerBody: { name: 'sent' } };
}
async function call(secret = 'synthetic-webhook-secret', payload = { type: 'INSERT', table: 'notifications', schema: 'public', record: { id: 'notice' } }) {
  return handler(new Request('https://example.invalid', {
    method: 'POST', headers: { ...(secret ? { 'x-webhook-secret': secret } : {}), 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  }));
}
let count = 0;
reset(); env.delete('PUSH_WEBHOOK_SECRET');
assert.equal((await (await call()).json()).error, 'WEBHOOK_SECRET_NOT_CONFIGURED'); count++;
reset(); assert.equal((await (await call(null)).json()).error, 'WEBHOOK_SECRET_HEADER_MISSING'); count++;
reset(); assert.equal((await (await call('wrong')).json()).error, 'WEBHOOK_SECRET_MISMATCH'); count++;
reset(); assert.equal((await call(undefined, { type: 'UPDATE' })).status, 400); count++;
reset(); config.approval = 'rejected';
assert.equal((await (await call()).json()).skipped, 'RECIPIENT_NOT_APPROVED'); assert.equal(fetches.length, 0); count++;
reset(); config.devices = [];
assert.equal((await (await call()).json()).skipped, 'NO_REGISTERED_DEVICES'); count++;
reset(); assert.equal((await (await call()).json()).sent, 1);
assert.equal(fetches[0].message.android.notification.channel_id, 'leave_requests'); count++;
reset(); config.providerStatus = 404; config.providerBody = { error: { details: [{ errorCode: 'UNREGISTERED' }] } };
await call(); assert.equal(removed, 1); count++;
reset(); config.providerStatus = 403; config.providerBody = { error: { details: [{ errorCode: 'SENDER_ID_MISMATCH' }] } };
assert.equal((await call()).status, 502);
assert.ok(JSON.stringify(logs).includes('SENDER_ID_MISMATCH'));
assert.ok(!JSON.stringify(logs).includes('synthetic-device-token')); count++;
reset(); env.set('FCM_SERVICE_ACCOUNT_JSON', 'invalid-json');
assert.equal((await (await call()).json()).stage, 'firebase_credentials'); count++;
console.log(`${count} push handler checks passed with mocked network and credentials.`);
