// Isolated PostgreSQL security regression checks. Requires @electric-sql/pglite.
// node scripts/test_access_hardening.mjs /absolute/path/to/pglite/dist/index.js
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
process.on('uncaughtException', (error) => { console.error(error.message, error.code || '', error.stack?.split('\n').filter(line => line.includes('test_access_hardening')).join('\n')); process.exit(1); });
const { PGlite } = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
await db.exec(read('supabase/tests/access_hardening_fixture.sql'));
await db.exec(read('supabase/tests/leave_workflow_fixture.sql'));
await db.exec(read('supabase/tests/business_functions_baseline.sql'));
await db.exec('create publication supabase_realtime;');
const stability = process.argv.includes('--stability');
const combined = process.argv.includes('--combined') || stability;
await db.exec(read(stability ? 'supabase/deploy/stability_release.sql' : combined ? 'supabase/deploy/core_hr_release.sql' : 'supabase/deploy/phase1_release.sql'));
const ids = {
  employee: '10000000-0000-0000-0000-000000000001',
  peer: '10000000-0000-0000-0000-000000000002',
  outsider: '10000000-0000-0000-0000-000000000003',
  pending: '10000000-0000-0000-0000-000000000004',
  hr: '10000000-0000-0000-0000-000000000005',
};
for (const [name, id] of Object.entries(ids)) {
  await db.query('insert into auth.users(id) values ($1)', [id]);
  await db.query('insert into profiles(id, full_name, role, approval_status) values ($1,$2,$3,$4)',
    [id, name, name === 'hr' ? 'hr' : 'employee', name === 'pending' ? 'pending' : 'approved']);
}
let count = 0;
async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [ids[name] || '']);
  await db.exec('set role ' + (name === 'anon' ? 'anon' : 'authenticated'));
}
async function denied(sql, args = []) {
  await assert.rejects(() => db.query(sql, args), (error) => error.code === '42501');
  count++;
}
await as('pending');
await denied("update profiles set approval_status='approved' where id=$1", [ids.pending]);
await denied('select register_push_token($1)', ['x'.repeat(40)]);
await as('employee');
await denied("update profiles set role='super_admin' where id=$1", [ids.employee]);
await denied('update profiles set manager_id=$1 where id=$2', [ids.outsider, ids.employee]);
await denied("update profiles set profile_details='{" + '"employment_type":"contractor"' + "}' where id=$1", [ids.employee]);
await db.query('update profiles set phone=$1 where id=$2', ['123', ids.employee]); count++;
await denied("insert into holidays(name,holiday_date,type) values ('Forged','2026-11-04','Company')");
await denied('truncate profiles cascade');
const { rows } = await db.query('select create_direct_conversation($1) as id', [ids.peer]);
const chat = rows[0].id;
const again = await db.query('select create_direct_conversation($1) as id', [ids.peer]);
assert.equal(again.rows[0].id, chat); count++;
await db.query('insert into messages(conversation_id,sender_id,message) values ($1,$2,$3)', [chat, ids.employee, 'Private']);
count++;
await as('outsider');
for (const table of ['messages', 'conversations', 'conversation_participants']) {
  assert.equal((await db.query('select * from ' + table)).rows.length, 0); count++;
}
await denied('insert into conversation_participants(conversation_id,user_id) values ($1,$2)', [chat, ids.outsider]);
await denied('insert into messages(conversation_id,sender_id,message) values ($1,$2,$3)', [chat, ids.outsider, 'Forged']);
await as('peer');
assert.equal((await db.query('select * from messages')).rows.length, 1); count++;
await as('hr');
assert.equal((await db.query('select * from messages')).rows.length, 0); count++;
await db.query("update profiles set approval_status='approved' where id=$1", [ids.pending]); count++;
await db.query("insert into holidays(name,holiday_date,type) values ('Company day','2026-11-04','Company')"); count++;
await as('anon');
await denied('truncate conversations cascade');
await denied('select create_direct_conversation($1)', [ids.employee]);
await db.exec('reset role');
assert.equal((await db.query("select * from pg_publication_tables where pubname='supabase_realtime' and tablename='messages'")).rows.length, 1); count++;
// Leave workflow: authorization, server quantity, stages, balance and idempotency.
await as('hr');
await db.query('update profiles set manager_id=$1 where id=$2', [ids.peer, ids.employee]);
await assert.rejects(() => db.query('update profiles set manager_id=$1 where id=$2', [ids.employee, ids.peer]), (error) => error.code === '22023'); count++;
await as('employee');
await assert.rejects(() => db.query("select review_employee($1,'approved')", [ids.outsider])); count++;
await assert.rejects(() => db.query("select assign_employee_role($1,'hr')", [ids.outsider])); count++;
await as('hr');
await db.query('select set_employee_leave_balance($1,$2,$3)', [ids.employee, 'Annual', 10]);
await as('employee');
await assert.rejects(() => db.query("select apply_for_leave('Annual','2026-11-10','2026-11-12',1,'Trip')")); count++;
const request = (await db.query("select apply_for_leave('Annual','2026-11-10','2026-11-12',3,'Trip') as id")).rows[0].id;
await assert.rejects(() => db.query("select apply_for_leave('Annual','2026-11-11','2026-11-13',3,'Overlap')")); count++;
await db.exec('reset role');
async function scalar(sql, args = []) { return Object.values((await db.query(sql, args)).rows[0])[0]; }
assert.equal(await scalar("select used_days from leave_balances where employee_id=$1", [ids.employee]), '0'); count++;
assert.equal(await scalar('select count(*) from notifications where recipient_id=$1 and leave_request_id=$2', [ids.peer, request]), 1); count++;
assert.equal(await scalar('select count(*) from notifications where recipient_id=$1 and leave_request_id=$2', [ids.hr, request]), 0); count++;
await as('outsider');
await denied("select review_leave_by_manager($1,'approved',null)", [request]);
await as('hr');
await assert.rejects(() => db.query("select review_leave_by_hr($1,'approved',null)", [request])); count++;
await as('peer');
await db.query("select review_leave_by_manager($1,'approved',null)", [request]);
await db.exec('reset role');
assert.equal(await scalar("select used_days from leave_balances where employee_id=$1", [ids.employee]), '0'); count++;
assert.equal(await scalar("select count(*) from notifications where recipient_id=$1 and event_type='leave.hr.pending'", [ids.hr]), 1); count++;
await as('hr');
await db.query("select review_leave_by_hr($1,'approved',null)", [request]);
await assert.rejects(() => db.query("select review_leave_by_hr($1,'approved',null)", [request])); count++;
await db.exec('reset role');
assert.equal(await scalar("select used_days from leave_balances where employee_id=$1", [ids.employee]), '3'); count++;
assert.equal(await scalar("select count(*) from notifications where recipient_id=$1 and leave_request_id=$2", [ids.employee, request]), 2); count++;
await as('employee');
const rejected = (await db.query("select apply_for_leave('Annual','2026-11-20','2026-11-21',2,'Trip') as id")).rows[0].id;
await as('peer');
await db.query("select review_leave_by_manager($1,'rejected',null)", [rejected]);
await db.exec('reset role');
assert.equal(await scalar('select count(*) from notifications where recipient_id=$1 and leave_request_id=$2', [ids.hr, rejected]), 0); count++;
assert.equal(await scalar("select used_days from leave_balances where employee_id=$1", [ids.employee]), '3'); count++;
await as('employee');
const tooLong = (await db.query("select apply_for_leave('Annual','2026-12-01','2026-12-10',10,'Trip') as id")).rows[0].id;
await as('peer');
await db.query("select review_leave_by_manager($1,'approved',null)", [tooLong]);
await as('hr');
await assert.rejects(() => db.query("select review_leave_by_hr($1,'approved',null)", [tooLong])); count++;
await db.exec('reset role');
assert.equal(await scalar('select hr_status from leave_requests where id=$1', [tooLong]), 'pending'); count++;
assert.equal(await scalar("select used_days from leave_balances where employee_id=$1", [ids.employee]), '3'); count++;
// Upgrade an already-used Phase 1 schema: preserve historic quantities, no fake audit.
if (!combined) await db.exec(read('supabase/migrations/202611030007_leave_ranges_cancellation_history.sql'));
assert.equal(await scalar('select approved_days from leave_requests where id=$1', [request]), '3'); count++;
assert.equal(await scalar('select count(*) from leave_request_history where request_id=$1', [request]), combined ? 3 : 0); count++;
// Date-range approval and cancellation use future dates independent of test day.
await as('employee');
const partial = (await db.query("select apply_for_leave('Annual','2099-01-10','2099-01-14',5,'Future trip') as id")).rows[0].id;
await as('peer');
await db.query("select review_leave_by_manager($1,'approved',null)", [partial]);
await as('hr');
await assert.rejects(() => db.query("select review_leave_by_hr_range($1,'approved',null,'2099-01-09','2099-01-12')", [partial])); count++;
await db.query("select review_leave_by_hr_range($1,'approved','Three dates','2099-01-11','2099-01-13')", [partial]);
await db.exec('reset role');
assert.equal(await scalar('select approved_days from leave_requests where id=$1', [partial]), '3'); count++;
assert.equal(await scalar('select used_days from leave_balances where employee_id=$1', [ids.employee]), '6'); count++;
assert.equal(await scalar('select count(*) from leave_request_history where request_id=$1', [partial]), 3); count++;
await as('employee');
// A day outside the approved subset is available despite being requested before.
const unused = (await db.query("select apply_for_leave('Annual','2099-01-10','2099-01-10',1,'Unused date') as id")).rows[0].id;
await assert.rejects(() => db.query("select apply_for_leave('Annual','2099-01-12','2099-01-12',1,'Overlap')")); count++;
await as('outsider');
await denied("select cancel_leave_request($1,'Unauthorized')", [partial]);
assert.equal((await db.query('select * from leave_request_history where request_id=$1', [partial])).rows.length, 0); count++;
await denied('delete from leave_request_history');
await as('employee');
await db.query("select cancel_leave_request($1,'Plans changed')", [partial]);
await assert.rejects(() => db.query("select cancel_leave_request($1,'Repeated')", [partial])); count++;
await db.exec('reset role');
assert.equal(await scalar('select used_days from leave_balances where employee_id=$1', [ids.employee]), '3'); count++;
assert.equal(await scalar('select count(*) from leave_request_history where request_id=$1', [partial]), 4); count++;
assert.equal(await scalar("select count(*) from notifications where recipient_id=$1 and leave_request_id=$2 and event_type='leave.cancelled'", [ids.employee, partial]), 1); count++;
await as('employee');
await db.query("select cancel_leave_request($1,'Withdraw pending')", [unused]);
await as('peer');
await assert.rejects(() => db.query("select review_leave_by_manager($1,'approved',null)", [unused])); count++;
await as('employee');
const historical = (await db.query("select apply_for_leave('Annual','2000-01-01','2000-01-02',2,'Historical request') as id")).rows[0].id;
await assert.rejects(() => db.query("select cancel_leave_request($1,'Past request')", [historical])); count++;
await db.exec('reset role');
assert.equal(await scalar('select used_days from leave_balances where employee_id=$1', [ids.employee]), '3'); count++;
await db.exec('reset role');
await db.query("insert into company_wall_posts(author_id,content) values ($1,'Synthetic policy test')", [ids.employee]);
// Stability release: revoked accounts fail closed and approved seats stop at 50.
if (!stability) await db.exec(read('supabase/migrations/202611030008_session_access_and_employee_capacity.sql'));
await db.exec('reset role');
await db.query("select set_config('request.jwt.claim.sub','',false)");
await db.query("update profiles set approval_status='rejected' where id=$1", [ids.outsider]);
await as('outsider');
assert.equal((await db.query('select * from holidays')).rows.length, 0); count++;
assert.equal((await db.query('select * from company_wall_posts')).rows.length, 0); count++;
await denied("insert into company_wall_posts(author_id,content) values ($1,'Denied test')", [ids.outsider]);
await as('peer');
assert.equal((await db.query('select * from company_wall_posts')).rows.length, 1); count++;
await as('outsider');
assert.equal((await db.query('select * from profiles where id=$1', [ids.outsider])).rows.length, 1); count++;
await db.exec('reset role');
await db.query("select set_config('request.jwt.claim.sub','',false)");
const approved = Number(await scalar("select count(*) from profiles where approval_status='approved'"));
for (let i = approved; i < 50; i++) {
  const id = `20000000-0000-0000-0000-${String(i).padStart(12,'0')}`;
  await db.query('insert into auth.users(id) values ($1)', [id]);
  await db.query("insert into profiles(id,full_name,role,approval_status) values ($1,'Synthetic capacity fixture','employee','approved')", [id]);
}
await db.query("insert into auth.users(id) values ('30000000-0000-0000-0000-000000000001')");
await db.query("insert into profiles(id,full_name,approval_status) values ('30000000-0000-0000-0000-000000000001','Waiting account','pending')");
await as('hr');
await assert.rejects(() => db.query("select review_employee('30000000-0000-0000-0000-000000000001','approved')"), (error) => error.code === '23514'); count++;
await db.query("select review_employee($1,'rejected')", [ids.pending]);
await db.query("select review_employee('30000000-0000-0000-0000-000000000001','approved')"); count++;
await db.exec('reset role');
assert.equal(Number(await scalar("select count(*) from profiles where approval_status='approved'")), 50); count++;
console.log(`${count} PostgreSQL security and leave workflow checks passed in an isolated fixture database.`);
await db.close();
