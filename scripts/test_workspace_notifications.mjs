// No live messages: isolated PostgreSQL tests of real trigger/RPC migrations.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2] || '@electric-sql/pglite');
const db=new PGlite();
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
await db.exec(`
create role anon; create role authenticated; create schema auth; create schema storage;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth,storage to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;
create table profiles(id uuid primary key,full_name text,approval_status text,role text,manager_id uuid);
create function public.has_approved_account() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=auth.uid() and approval_status='approved') $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security; grant select,insert,delete on storage.objects to authenticated;
create table notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid references profiles(id),leave_request_id text not null,title text not null,body text not null,event_type text not null default 'leave.applied',event_key text not null,category text not null default 'leave',priority text not null default 'normal',destination text not null default 'leave',target_id_dummy text,created_at timestamptz default now(),read_at timestamptz,dismissed_at timestamptz,unique(recipient_id,event_key));
alter table notifications enable row level security; grant select on notifications to authenticated;
create policy own_notices on notifications for select to authenticated using(recipient_id=auth.uid() and has_approved_account());
create table tasks(id uuid primary key default gen_random_uuid(),creator_id uuid,assignee_id uuid,status text);
create table messages(id uuid primary key default gen_random_uuid(),conversation_id uuid,sender_id uuid,message text);
create table conversation_participants(conversation_id uuid,user_id uuid,primary key(conversation_id,user_id));
create table attendance_adjustment_requests(id uuid primary key default gen_random_uuid(),employee_id uuid,status text default 'pending');
create table attendance_correction_requests(id uuid primary key default gen_random_uuid(),employee_id uuid,status text default 'pending');
create table company_wall_posts(id uuid primary key default gen_random_uuid(),author_id uuid,post_type text);
`);
await db.exec(read('supabase/migrations/202611040001_hr_modules.sql'));
await db.exec(read('supabase/migrations/202611040002_limit_hr_modules.sql'));
await db.exec(read('supabase/migrations/202611040003_workspace_notifications.sql'));
const ids=Object.fromEntries(['employee','peer','hr','admin','pending','manager'].map((name,i)=>[name,`10000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`]));
for(const [name,id] of Object.entries(ids)) await db.query('insert into profiles values($1,$2,$3,$4,$5)',[id,name,name==='pending'?'pending':'approved',['hr','admin'].includes(name)?name:name==='manager'?'management':'employee',name==='employee'?ids.manager:null]);
let count=0;
async function as(name) {await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]||'']);await db.exec(`set role ${name==='anon'?'anon':'authenticated'}`);}
async function root(name) {await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]||'']);}
async function notices(type,target) {await db.exec('reset role');return (await db.query('select * from notifications where event_type=$1 and target_id=$2 order by recipient_id',[type,target])).rows;}
function recipients(rows,names) {assert.deepEqual(rows.map(r=>r.recipient_id).sort(),names.map(n=>ids[n]).sort());count++;}
async function create(module,data,subject=ids.employee,wide=false) {return (await db.query('select hr_create_record($1,$2,$3,$4,$5,$6) id',[module,subject,'PRIVATE TITLE','PRIVATE DETAILS',JSON.stringify(data),wide])).rows[0].id;}
async function update(id,action,patch={}) {const r=(await db.query('select * from hr_records where id=$1',[id])).rows[0];await db.query('select hr_update_record($1,$2,$3,$4,$5)',[id,r.revision,action,'PRIVATE NOTE',JSON.stringify(patch)]);}
async function attachment(id) {await db.exec('reset role');await db.query("insert into hr_attachments(record_id,uploaded_by,name,path) values($1,$2,'PRIVATE FILE.pdf',$3)",[id,ids.hr,`${id}/private.pdf`]);}
await as('employee');await assert.rejects(()=>db.query("select emit_workspace_notification($1,'fake','fake','ticket','x','fake','fake')",[ids.peer]));count++;
await as('hr');const onboard=await create('onboarding',{joining_date:'2026-11-04',buddy:'PRIVATE BUDDY'});
recipients(await notices('onboarding.assigned',onboard),['employee']);
await as('employee');await update(onboard,'save',{checklist:[true,true,true,true]});
assert.equal((await notices('onboarding.completed',onboard)).length,0);count++;
await as('employee');await update(onboard,'completed');
recipients(await notices('onboarding.completed',onboard),['hr','admin']);
await as('hr');const salary=await create('payslip',{period:'2026-11',basic:'9999',allowances:'0',deductions:'0'});
assert.equal((await notices('payslip.published',salary)).length,0);count++;
await attachment(salary);await as('hr');await update(salary,'published');recipients(await notices('payslip.published',salary),['employee']);
await as('hr');const doc=await create('document',{category:'Private letter',version:'1'});await attachment(doc);await as('hr');await update(doc,'published');recipients(await notices('document.published',doc),['employee']);
await as('employee');await db.query('select hr_acknowledge($1)',[doc]);await db.query('select hr_acknowledge($1)',[doc]);recipients(await notices('document.acknowledged',doc),['hr']);
await as('hr');const policy=await create('document',{category:'Policy',version:'1'},ids.employee,true);await attachment(policy);await as('hr');await update(policy,'published');recipients(await notices('document.published',policy),['employee','peer','admin','manager']);
await as('peer');await db.query('select hr_acknowledge($1)',[policy]);assert.equal((await notices('document.acknowledged',policy)).length,0);count++;
await as('employee');const ticket=await create('ticket',{category:'HR',priority:'High'});recipients(await notices('ticket.created',ticket),['hr','admin']);
assert.equal((await notices('ticket.created_for_you',ticket)).length,0);count++;
await as('hr');await update(ticket,'in_progress');recipients(await notices('ticket.in_progress',ticket),['employee']);
await as('hr');await update(ticket,'resolved');recipients(await notices('ticket.resolved',ticket),['employee']);
await as('employee');await update(ticket,'open');recipients(await notices('ticket.reopened',ticket),['hr','admin']);
await as('hr');await update(ticket,'resolved');assert.equal((await notices('ticket.resolved',ticket)).length,2);count++;
await root('hr');const task=(await db.query("insert into tasks(creator_id,assignee_id,status) values($1,$2,'pending_acceptance') returning id",[ids.hr,ids.employee])).rows[0].id;recipients(await notices('task.assigned',task),['employee']);
await root('employee');await db.query("update tasks set status='in_progress' where id=$1",[task]);recipients(await notices('task.in_progress',task),['hr']);
await root('employee');await db.query("update tasks set status='in_progress' where id=$1",[task]);assert.equal((await notices('task.in_progress',task)).length,1);count++;
await root('employee');await db.query("update tasks set status='completed' where id=$1",[task]);recipients(await notices('task.completed',task),['hr']);
await root('hr');await db.query("update tasks set assignee_id=$1,status='blocked' where id=$2",[ids.peer,task]);
recipients(await notices('task.assigned',task),['employee','peer']);
assert.equal((await notices('task.blocked',task)).length,0);count++;
const conversation='20000000-0000-0000-0000-000000000001';await root('employee');
for(const member of ['employee','peer','pending']) await db.query('insert into conversation_participants values($1,$2)',[conversation,ids[member]]);
await db.query('insert into messages(conversation_id,sender_id,message) values($1,$2,$3)',[conversation,ids.employee,'PRIVATE CHAT CONTENT']);
recipients(await notices('chat.message',conversation),['peer']);
for(const table of ['attendance_adjustment_requests','attendance_correction_requests']) {
  await root('employee');const request=(await db.query(`insert into ${table}(employee_id) values($1) returning id`,[ids.employee])).rows[0].id;
  recipients(await notices('attendance.submitted',request),['hr','admin','manager']);
  await root('hr');await db.query(`update ${table} set status='approved' where id=$1`,[request]);recipients(await notices('attendance.approved',request),['employee']);
}
await root('hr');const post=(await db.query("insert into company_wall_posts(author_id,post_type) values($1,'post') returning id",[ids.hr])).rows[0].id;assert.equal((await notices('company.announcement',post)).length,0);count++;
await root('hr');const announcement=(await db.query("insert into company_wall_posts(author_id,post_type) values($1,'announcement') returning id",[ids.hr])).rows[0].id;recipients(await notices('company.announcement',announcement),['employee','peer','admin','manager']);
await root('employee');const ordinaryAnnouncement=(await db.query("insert into company_wall_posts(author_id,post_type) values($1,'announcement') returning id",[ids.employee])).rows[0].id;
assert.equal((await notices('company.announcement',ordinaryAnnouncement)).length,0);count++;
await db.exec('reset role');const all=(await db.query('select * from notifications')).rows;
assert.ok(all.every(n=>!`${n.title} ${n.body}`.includes('PRIVATE')));assert.ok(all.every(n=>!n.body.includes('9999')));count++;
assert.equal(new Set(all.map(n=>`${n.recipient_id}:${n.event_key}`)).size,all.length);count++;
await as('employee');assert.ok((await db.query('select * from notifications')).rows.every(n=>n.recipient_id===ids.employee));count++;
await as('pending');assert.equal((await db.query('select * from notifications')).rows.length,0);count++;
await db.exec('reset role');await db.exec("insert into notifications(recipient_id,leave_request_id,title,body,event_key) values('10000000-0000-0000-0000-000000000001','legacy-leave','Leave','Existing leave flow','legacy:leave')");
assert.equal((await db.query("select destination from notifications where event_key='legacy:leave'")).rows[0].destination,'leave');count++;
console.log(`${count} workspace notification checks passed`);await db.close();
