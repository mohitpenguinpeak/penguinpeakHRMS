// Isolated PostgreSQL regression tests for employee visibility and delegation.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`
create role authenticated; create role anon; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select current_setting('request.jwt.claim.sub')::uuid$$;
grant usage on schema auth to authenticated;
create table profiles(id uuid primary key, full_name text,approval_status text,removed_at timestamptz);
create function has_approved_account() returns boolean language sql stable security definer as $$select exists(select from public.profiles where id=auth.uid() and approval_status='approved')$$;
create table tasks(id uuid primary key default gen_random_uuid(), creator_id uuid,assignee_id uuid,description text,status text,due_date date,created_at timestamptz default now());
create table leave_requests(employee_id uuid,manager_status text,hr_status text,cancelled_at timestamptz,start_date date,end_date date,approved_start_date date,approved_end_date date);
alter table tasks enable row level security;
create policy own_tasks on tasks for select to authenticated using(auth.uid() in (creator_id,assignee_id));
grant select, insert on tasks to authenticated;
`);
await db.exec(readFileSync(new URL('../supabase/migrations/202611170001_resource_availability_subtasks.sql',import.meta.url),'utf8'));
const ids = Array.from({length:4},(_,i)=>'10000000-0000-0000-0000-00000000000'+(i+1));
const [creator,assignee,peer,pending] = ids;
for(const id of ids) await db.query('insert into profiles values($1,$2,$3,null)',[id,id,id===pending?'pending':'approved']);
const parent = (await db.query("insert into tasks(creator_id,assignee_id,status,due_date,description) values($1,$2,'todo','2026-11-17','[Booking: 3.5 hrs] private') returning id",[creator,assignee])).rows[0].id;
await db.query("insert into leave_requests values($1,'approved','approved',null,'2026-11-17','2026-11-17',null,null)",[peer]);
async function login(id) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
  await db.exec('set role authenticated');
}
const availability = () => db.query("select * from resource_availability('2026-11-17',7)");
const insert = (creatorId,target) => db.query("insert into tasks(parent_task_id,creator_id,assignee_id,status) values($1,$2,$3,'todo') returning id",[parent,creatorId,target]);
await login(peer);
assert.equal((await db.query('select * from tasks')).rows.length,0);
const roster = (await availability()).rows;
assert.equal(roster.length,3);
assert.deepEqual(roster.find(r=>r.id===assignee).days['2026-11-17'],{hours:3.5,leave:false});
assert.equal(roster.find(r=>r.id===peer).days['2026-11-17'].leave,true);
await assert.rejects(()=>insert(peer,creator),/assignee/);
await login(assignee);
await assert.rejects(()=>insert(assignee,pending),/active assignee/);
const child = (await insert(assignee,peer)).rows[0].id;
await login(peer);
assert.equal((await db.query('select parent_task_id from tasks where id=$1',[child])).rows[0].parent_task_id,parent);
await login(pending);
await assert.rejects(availability,/Approved account/);
await db.exec('reset role');
await db.query('delete from tasks where id=$1',[parent]);
assert.equal((await db.query('select parent_task_id from tasks where id=$1',[child])).rows[0].parent_task_id,null);
await db.close();
console.log('Passed resource visibility, subtask authorization and parent deletion checks.');
