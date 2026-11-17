// Isolated PostgreSQL tests; never reads or writes a live Supabase project.
// node scripts/test_performance.mjs /absolute/path/to/pglite/dist/index.js
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
create table profiles(id uuid primary key,full_name text,department text,approval_status text,role text,manager_id uuid,joining_date date,created_at timestamptz);
create table company_attendance_settings(timezone text);
insert into company_attendance_settings values('Asia/Kolkata');
create table holidays(holiday_date date);
create table attendance_records(employee_id uuid,attendance_date date,check_in timestamptz,status text,late_minutes integer);
create table leave_requests(employee_id uuid,manager_status text,hr_status text,cancelled_at timestamptz,day_portion text,approved_start_date date,approved_end_date date,start_date date,end_date date);
create table tasks(assignee_id uuid,status text,due_date date,completed_at timestamptz);
`);
await db.exec(readFileSync(new URL('../supabase/migrations/202611160001_automated_performance.sql',import.meta.url),'utf8'));
const names = ['employee','peer','manager','hr','admin','super_admin','pending','null_status'];
const ids = Object.fromEntries(names.map((n,i)=>[n,`10000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`]));
for (const name of names) {
  await db.query('insert into profiles values($1,$2,$3,$4,$5,$6,$7,$8)',[
    ids[name],name,'Engineering',name==='pending'?'pending':name==='null_status'?null:'approved',
    ['hr','admin','super_admin'].includes(name)?name:name==='manager'?'management':'employee',
    name==='employee'?ids.manager:null,'2026-10-05','2026-10-01T00:00Z']);
}
await db.query(`insert into tasks values
 ($1,'completed','2026-10-05','2026-10-05T12:00Z'),
 ($1,'in_progress','2026-10-06',null),
 ($1,'completed','2026-10-07','2026-10-08T12:00Z'),
 ($1,'completed',null,'2026-10-08T12:00Z'),
 ($1,'declined','2026-10-05',null),
 ($1,'pending_acceptance','2026-10-06',null),
 ($1,'todo','2099-01-01',null),
 ($1,'completed','2026-10-02','2026-10-05T12:00Z')`,[ids.employee]);
await db.query(`insert into attendance_records values
 ($1,'2026-10-05','2026-10-05T03:30Z','Present',0),
 ($1,'2026-10-05','2026-10-05T03:30Z','Present',0),
 ($1,'2026-10-06','2026-10-06T04:30Z','Late',60),
 ($1,'2026-10-07','2026-10-07T03:30Z','Half Day',0)`,[ids.employee]);
await db.query(`insert into leave_requests values
 ($1,'approved','approved',null,'first_half',null,null,'2026-10-07','2026-10-07'),
 ($1,'approved','approved',null,'full_day','2026-10-08','2026-10-08','2026-10-08','2026-10-09')`,[ids.employee]);
await db.exec("insert into holidays values('2026-10-09')");
let checks = 0;
function equal(a,b) { assert.deepEqual(a,b); checks++; }
async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]||'']);
  await db.exec(`set role ${name==='anon'?'anon':'authenticated'}`);
}
async function report(period='weekly',anchor='2026-10-05',employee=null) {
  return (await db.query('select performance_scorecards($1,$2,$3) report',[period,anchor,employee])).rows[0].report;
}
async function denied(...args) { await assert.rejects(()=>report(...args)); checks++; }
await as('employee');
let r = await report(); let e = r.employees[0];
equal(r.employees.map(e=>e.id),[ids.employee]);
equal([r.start,r.end,r.timezone,r.provisional],['2026-10-05','2026-10-11','Asia/Kolkata',false]);
equal([e.task_count,e.completed_tasks,e.dated_tasks,e.on_time_tasks],[4,3,3,1]);
equal([e.expected_days,e.attended_days,e.punctual_days,e.on_time_days],[2.5,2.5,2,1]);
equal([e.score,e.available_weight],[69.2,100]);
await denied('weekly','2026-10-05',ids.peer);
await denied('weekly','2026-10-05',ids.hr);
await denied('invalid','2026-10-05');
await denied(null,'2026-10-05');
await denied('daily','2099-01-01');
await assert.rejects(()=>db.query('select * from tasks')); checks++;
// Same matrix, different calendar windows, no averaging of daily scores.
for (const [period,start,end] of [
 ['daily','2026-10-05','2026-10-05'],['weekly','2026-10-05','2026-10-11'],
 ['monthly','2026-10-01','2026-10-31'],['quarterly','2026-10-01','2026-12-31'],
 ['annually','2026-01-01','2026-12-31']]) {
  const x = await report(period,'2026-10-05');
  equal([x.start,x.end,x.matrix_version],[start,end,'v1']);
}
equal((await report('monthly','2024-02-12')).end,'2024-02-29');
// Leave/holiday/weekend are unavailable evidence, never an automatic perfect score.
for (const day of ['2026-10-08','2026-10-09','2026-10-10']) {
  const x = (await report('daily',day)).employees[0];
  equal(x.attendance,null);
}
await as('peer'); e = (await report('daily','2026-10-05')).employees[0];
equal([e.score,e.available_weight],[0,20]); // A scheduled closed day without attendance is an absence.
e = (await report('daily','2026-10-10')).employees[0];
equal([e.score,e.available_weight],[null,0]);
await as('manager'); equal((await report()).employees.map(e=>e.id).sort(),[ids.employee,ids.manager].sort());
await denied('monthly','2026-10-05',ids.peer);
for (const role of ['hr','admin','super_admin']) {
 await as(role); equal((await report()).employees.length,6);
 equal((await report('weekly','2026-10-05',ids.employee)).employees.length,1);
}
for (const role of ['pending','null_status','unknown','anon']) { await as(role); await denied(); }
// Overlapping legacy half-day rows are not two halves of leave. Pending and
// cancelled leave must not excuse an absence or remove attendance evidence.
await db.exec('reset role');
await db.query(`insert into leave_requests values
 ($1,'approved','approved',null,'first_half',null,null,'2026-10-07','2026-10-07'),
 ($1,'approved','pending',null,'full_day',null,null,'2026-10-06','2026-10-06'),
 ($1,'approved','approved',now(),'full_day',null,null,'2026-10-05','2026-10-05')`,[ids.employee]);
await as('employee'); e=(await report()).employees[0];
equal([e.expected_days,e.attended_days],[2.5,2.5]);
e=(await report('daily','2026-10-07')).employees[0];
equal([e.expected_days,e.attended_days,e.punctuality],[0.5,0.5,null]);
equal([e.completed_tasks,e.delivery],[0,0]); // Completion was recorded the next day.
// Missing completion dates: completion evidence exists but timeliness is unknown.
await db.exec('reset role');
await db.query("insert into tasks values($1,'completed','2026-10-05',null)",[ids.employee]);
await as('employee'); e=(await report()).employees[0];
equal([e.task_count,e.completed_tasks,e.dated_tasks,e.unknown_completion_dates],[5,4,3,1]);
// Corrections are automatically reflected; no stored score can go stale.
await db.exec('reset role');
await db.query("update attendance_records set late_minutes=0,status='Present' where employee_id=$1 and attendance_date='2026-10-06'",[ids.employee]);
await as('employee'); equal((await report()).employees[0].punctuality,100);
// Current daily report excludes a missing punch until the day ends, then includes an actual check-in.
const live = await report('daily',null); equal(live.provisional,true);
equal(live.employees[0].score,null);
await db.exec('reset role');
await db.exec('delete from holidays');
await db.query('insert into attendance_records values($1,$2,now(),$3,0)',[ids.employee,live.today,'Present']);
await as('employee');
e=(await report('daily',null)).employees[0];
const weekday = new Date(`${live.today}T00:00Z`).getUTCDay();
equal(e.score,weekday===0||weekday===6?null:100);
// Invalid company timezone safely falls back to UTC.
await db.exec('reset role'); await db.exec("update company_attendance_settings set timezone='invalid'");
await as('employee'); equal((await report()).timezone,'UTC');
console.log(`${checks} performance scoring, calendar, correction and access checks passed`);
await db.close();
