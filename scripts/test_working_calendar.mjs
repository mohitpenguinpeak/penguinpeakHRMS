// Runs against an empty in-memory PostgreSQL instance.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const {PGlite} = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
const load = path => db.exec(readFileSync(new URL('../supabase/' + path, import.meta.url), 'utf8'));
await load('tests/access_hardening_fixture.sql');
await load('tests/leave_workflow_fixture.sql');
await load('tests/business_functions_baseline.sql');
await db.exec('create publication supabase_realtime');
await load('deploy/core_hr_release.sql');
await load('migrations/202611130008_optional_unlimited_leave.sql');
await load('migrations/202611130009_half_day_leave.sql');
await load('migrations/202611160002_company_working_calendar.sql');
await load('migrations/202611160003_working_saturdays.sql');
const hr = '10000000-0000-0000-0000-000000000001';
const manager = '10000000-0000-0000-0000-000000000002';
const employee = '10000000-0000-0000-0000-000000000003';
for (const [id,role,reportsTo] of [[hr,'hr',null],[manager,'management',null],[employee,'employee',manager]]) {
  await db.query('insert into auth.users values ($1)',[id]);
  await db.query("insert into profiles(id,role,approval_status,manager_id) values ($1,$2,'approved',$3)",[id,role,reportsTo]);
}
async function login(id) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
  await db.exec('set role authenticated');
}
const scalar = async (sql,args = []) => Object.values((await db.query(sql,args)).rows[0])[0];
await login(hr);
await db.exec("insert into holidays(name,holiday_date,type) values ('Office closed','2026-12-02','Company Holiday'),('Saturday shift','2026-12-05','Working day')");
await assert.rejects(() => db.exec("insert into holidays(name,holiday_date) values ('Duplicate','2026-12-05')"), /already exists/);
await db.query("select set_employee_leave_allocation($1,'Annual',12,false)",[employee]);
await login(employee);
assert.equal(await scalar('select count(*) from holidays'),2);
assert.equal((await db.exec("delete from holidays where holiday_date='2026-12-05'"))[0].affectedRows,0);
for (const date of ['2026-12-02','2026-12-06','2026-12-19']) {
  await assert.rejects(() => db.query("select apply_for_leave_duration('Annual',$1,$1,'first_half','Test')",[date]), /working days/);
}
const request = await scalar("select apply_for_leave_duration('Annual','2026-12-01','2026-12-07','full_day','Test')");
assert.equal(Number(await scalar('select days from leave_requests where id=$1',[request])),5);
await db.exec('reset role');
await db.query("update leave_requests set manager_status='approved' where id=$1",[request]);
await login(hr);
await db.query("select review_leave_by_hr_range($1,'approved',null,'2026-12-03','2026-12-07')",[request]);
assert.equal(Number(await scalar('select used_days from leave_balances where employee_id=$1',[employee])),4);
await db.exec("delete from holidays where holiday_date='2026-12-05'");
assert.equal(await scalar("select company_is_workday('2026-12-05')"),false);
for (const day of ['2026-12-12','2026-12-26']) {
  assert.equal(Number(await scalar("select company_leave_days($1,$1,'full_day')",[day])),1);
}
await db.exec("insert into holidays(name,holiday_date) values ('Office closed','2026-12-12')");
assert.equal(await scalar("select company_is_workday('2026-12-12')"),false);
await db.exec("delete from holidays where holiday_date='2026-12-12'");
assert.equal(await scalar("select company_is_workday('2026-12-12')"),true);
await db.close();
console.log('Working calendar, access, leave submission and approval checks passed.');
