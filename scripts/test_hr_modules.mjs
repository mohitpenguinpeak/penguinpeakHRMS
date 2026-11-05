// Isolated database tests: node scripts/test_hr_modules.mjs /path/to/pglite/dist/index.js
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create schema auth; create schema storage;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth,storage to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;
create table public.profiles(id uuid primary key, full_name text, approval_status text, role text, manager_id uuid);
create function public.has_approved_account() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=auth.uid() and approval_status='approved' and role in ('employee','management','hr','admin','super_admin')) $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security; grant select,insert,delete on storage.objects to authenticated;
`);
await db.exec(readFileSync(new URL('../supabase/migrations/202611040001_hr_modules.sql', import.meta.url), 'utf8'));
const ids = Object.fromEntries(['employee','peer','manager','hr','pending','hr2'].map((n,i)=>[n,`10000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`]));
for (const [name,id] of Object.entries(ids)) await db.query('insert into profiles values($1,$2,$3,$4,$5)',[id,name,name==='pending'?'pending':'approved',name.startsWith('hr')?'hr':name==='manager'?'management':'employee',name==='employee'?ids.manager:null]);
let passed=0;
async function as(name) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name] || '']); await db.exec(`set role ${name==='anon'?'anon':'authenticated'}`); }
async function denied(sql,args=[]) { await assert.rejects(()=>db.query(sql,args)); passed++; }
async function create(module,data,employee=ids.employee,company=false) { return (await db.query('select hr_create_record($1,$2,$3,$4,$5,$6) id',[module,employee,`${module} test`,'Saved details',JSON.stringify(data),company])).rows[0].id; }
async function get(id) { return (await db.query('select * from hr_records where id=$1',[id])).rows[0]; }
async function update(id,action,note='Decision recorded',patch={}) { const r=await get(id); return db.query('select hr_update_record($1,$2,$3,$4,$5)',[id,r.revision,action,note,JSON.stringify(patch)]); }
async function attach(id,name='receipt.pdf') {
  const actor=(await db.query('select auth.uid() id')).rows[0].id;
  const path=`${id}/${actor}/${name}`;
  await db.query("insert into storage.objects(bucket_id,name) values('hr-private',$1)",[path]);
  await db.query('select hr_register_attachment($1,$2,$3)',[id,name,path]);
  return path;
}
// Simulate an already deployed earlier release, then narrow without deleting data.
await db.exec('reset role');
const retired = [];
for (const module of ['expense','shift','swap','performance','asset','offboarding']) {
  const r = await db.query("insert into hr_records(module,employee_id,created_by,title,status) values($1,$2,$2,'Old record','submitted') returning id",[module,ids.employee]);
  retired.push(r.rows[0].id);
}
const retiredPath = `${retired[0]}/${ids.employee}/old.pdf`;
await db.query("insert into storage.objects(bucket_id,name) values('hr-private',$1)",[retiredPath]);
await db.query("insert into hr_attachments(record_id,uploaded_by,name,path) values($1,$2,'old.pdf',$3)",[retired[0],ids.employee,retiredPath]);
await db.exec(readFileSync(new URL('../supabase/migrations/202611040002_limit_hr_modules.sql', import.meta.url), 'utf8'));
await as('pending'); await denied("select hr_create_record('ticket',$1,'x','', $2,false)",[ids.pending,JSON.stringify({category:'HR',priority:'High'})]);
await as('anon'); await denied('select * from hr_records');
await as('hr');
for (const module of ['expense','shift','swap','performance','asset','offboarding']) {
  await denied('select hr_create_record($1,$2,$3,$4,$5,false)',[module,ids.employee,'Removed','', '{}']);
}
for (const id of retired) {
  assert.equal(await get(id),undefined); passed++;
  await denied('select hr_update_record($1,1,$2,$3,$4)',[id,'approved','Retired','{}']);
  assert.equal((await db.query('select hr_can_attach($1) ok',[id])).rows[0].ok,false); passed++;
}
assert.equal((await db.query('select * from storage.objects')).rows.length,0); passed++;
await as('employee');
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[retiredPath])).rows.length,0); passed++;
await denied("insert into hr_records(module,employee_id,created_by,title,status) values('ticket',$1,$1,'Forged','closed')",[ids.employee]);
await denied("select hr_create_record('payslip',$1,'Forged','', '{}',false)",[ids.employee]);
await denied("select hr_create_record('ticket',$1,'Other employee','', $2,false)",[ids.peer,JSON.stringify({category:'HR',priority:'High'})]);
await as('hr');
const payslip=await create('payslip',{period:'2026-11',basic:'10000',allowances:'2000',deductions:'500'});
await denied('select hr_update_record($1,1,$2,$3,$4)',[payslip,'published','','{}']);
await as('employee'); assert.equal(await get(payslip),undefined); passed++;
await as('hr'); const salaryPath=await attach(payslip,'salary.pdf'); await update(payslip,'published');
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[salaryPath])).rows.length,0); passed++;
await as('employee'); assert.equal((await get(payslip)).status,'published'); passed++;
assert.equal((await db.query('select * from storage.objects where name=$1',[salaryPath])).rows.length,1); passed++;
await as('peer'); assert.equal(await get(payslip),undefined); passed++;
assert.equal((await db.query('select * from storage.objects')).rows.length,0); passed++;
await denied('select hr_acknowledge($1)',[payslip]);
await as('hr');
await denied("select hr_create_record('payslip',$1,'Invalid','', $2,false)",[ids.peer,JSON.stringify({period:'2026-11',basic:'1000',allowances:'0',deductions:'2000'})]);
const policy=await create('document',{category:'Policy',version:'1'},ids.employee,true); await attach(policy,'policy.pdf'); await update(policy,'published');
await as('peer'); await db.query('select hr_acknowledge($1)',[policy]); await db.query('select hr_acknowledge($1)',[policy]);
assert.equal((await db.query('select * from hr_acknowledgements')).rows.length,1); passed++;
await as('hr'); const onboarding=await create('onboarding',{joining_date:'2026-11-04',buddy:'Buddy'});
await as('employee'); await denied('select hr_update_record($1,1,$2,$3,$4)',[onboarding,'completed','','{}']);
await denied('select hr_update_record($1,1,$2,$3,$4)',[onboarding,'save','',JSON.stringify({checklist:[true,true,true,'yes']})]);
await update(onboarding,'save','',{checklist:[true,true,true,true]});
await denied('select hr_update_record($1,1,$2,$3,$4)',[onboarding,'completed','','{}']);
await update(onboarding,'completed'); passed++;
const ticket=await create('ticket',{category:'IT',priority:'High'});
const orphanPath=`${ticket}/${ids.employee}/orphan.pdf`;
await db.query("insert into storage.objects(bucket_id,name) values('hr-private',$1)",[orphanPath]);
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[orphanPath])).rows.length,1); passed++;
await as('manager'); assert.equal(await get(ticket),undefined); passed++;
await as('hr'); await update(ticket,'in_progress');
await denied('select hr_update_record($1,2,$2,$3,$4)',[ticket,'resolved','','{}']);
await update(ticket,'resolved');
await as('employee'); await update(ticket,'open');
await as('hr'); await update(ticket,'resolved');
await as('employee'); await update(ticket,'closed'); passed++;
await db.exec('reset role');
assert.equal((await db.query("select count(*)::int n from hr_records where module not in ('onboarding','payslip','ticket','document')")).rows[0].n,6); passed++;
await db.query("update profiles set approval_status='rejected' where id=$1",[ids.employee]);
await as('employee'); assert.equal((await db.query('select * from hr_records')).rows.length,0); passed++;
assert.equal((await db.query('select * from storage.objects')).rows.length,0); passed++;
console.log(`${passed} selected HR workflow/security checks passed`);
await db.close();
