# Phase 1 security rollout — prepared, not applied

## Findings confirmed by the supplied metadata

- `profiles_update_by_owner_or_hr` permits owners to update their row, and the
  authenticated role has UPDATE on `approval_status`. Without a further guard
  (none appears in the exported public triggers), owners can approve themselves.
  Role UPDATE is not directly granted in this snapshot; do not confuse that with
  verification of the security-definer role-assignment RPC, whose body is pending.
- Participants can be inserted with `WITH CHECK true`. A signed-in user can add
  themselves to a known conversation and satisfy the message membership policy.
  Conversation and participant SELECT policies also disclose their metadata to
  all authenticated accounts. HR status must not confer private chat access.
- Holiday `ALL` policy uses `true` despite its admin/HR policy name.
- Client roles have TRUNCATE privileges. RLS does not restrict TRUNCATE; remove
  the grant even though ordinary PostgREST table endpoints do not expose arbitrary
  SQL/TRUNCATE execution.
- No public tables are members of `supabase_realtime` in the export. Chat's
  subscription is present in code but cannot receive inserts through that publication.
- The snapshot still gives anonymous EXECUTE on register_push_token. Its body
  must validate UID, and migration 004 additionally revokes this entry point and
  enforces approved-account eligibility.

## Prepared changes

Apply migration 004 (approved push registration) and then 005 (access hardening).
005 runs in a transaction, preserves all rows, retains personal profile editing,
restricts employment/approval changes, replaces the known unsafe holiday/chat
policies, and adds an atomic direct-conversation RPC. Same-pair requests are
serialized with a transaction advisory lock and reuse existing direct chats.
Existing conversations/memberships are preserved, including any historically
unauthorized memberships; review those privately. The migration cannot infer
which past memberships were legitimate and does not silently remove any.

Client chat creation now uses the RPC. Non-HR profile editors disable department,
designation, manager, joining date and controlled employment details. The server
trigger is authoritative; UI disabling is not the security boundary. Group chat
creation/member administration is not implemented by this change.

## Staging procedure and deployment order

1. Use a staging copy with equivalent schema/policies and synthetic accounts.
   Back up production schema/grants/policies through your normal secure workflow.
2. Apply only missing migrations 004 and 005. Do not replay the full earlier
   migration directory on production: some migrations intentionally CREATE tables.
3. Run the role scenarios below using actual authenticated client JWTs. The
   SQL editor's postgres role bypasses RLS and is not a valid permission test.
4. Verify existing HR/admin approval/edit workflows and personal profile/photo
   editing. Inspect privileged business RPC source with the allowlisted audit
   before trusting them. Trigger guards also affect SECURITY DEFINER RPC writes.
5. Verify chat history/creation/reuse and cross-user isolation. Update clients
   immediately after applying 005: old clients' direct chat creation is denied.
   Prefer a coordinated maintenance release; do not retain unsafe membership
   insertion as a compatibility fallback. Offline clients must update before
   creating new conversations.
6. Promote the same SQL and new client build only after staging checks pass.
   No security change has been applied to production by this chat.

## Validation scenarios

- Pending user cannot approve themselves or register a device; approved employee
  cannot change manager, role or controlled employment fields.
- Approved employee can edit phone/personal details; approved HR can approve an
  employee and manage employment fields/holidays.
- Unrelated user cannot list another chat's messages, conversations or members,
  join it, or send to it. A participant can read/send. HR who is not a participant
  cannot read it. Pending users are denied.
- Concurrent attempts for the same direct-chat pair reuse one conversation.
  The fixture tests sequential reuse, not cross-connection concurrency.
- Client roles cannot TRUNCATE, and only messages is added to Realtime.
- Actual clients receive only messages they are authorized to read; verify using
  separate sessions. Fixture catalog tests do not prove hosted Realtime delivery.

## Isolated test evidence and limits

`node scripts/test_access_hardening.mjs <absolute PGlite dist/index.js path>` runs
22 assertions against a temporary PostgreSQL fixture. Install the reputable test
runtime outside the repository, for example:

```bash
npm install --prefix /tmp/penguinpeak-sql-validation @electric-sql/pglite
node scripts/test_access_hardening.mjs /tmp/penguinpeak-sql-validation/node_modules/@electric-sql/pglite/dist/index.js
```

The fixture SQL under `supabase/tests` is **test-only** and must never be run in
Supabase production. It reconstructs relevant metadata and uses stub auth/role
helpers, deliberately broad client table privileges and synthetic users. It is
not a copy of production data or an end-to-end test of live business RPCs.
The complete migrations 004 and 005 executed in the fixture, including the
publication change. 22 checks passed; seven Flutter regressions passed.

## Rollback

The security changes deliberately have no automatic rollback to the unsafe
policies. If a rollout fails, investigate in staging or restore a reviewed schema
backup during maintenance. Do not re-enable unrestricted membership insertion or
self-approval to make an old client work. No existing rows were dropped by 005.

## Outstanding work

Run `supabase/audit/business_function_definitions.sql` and export its single JSON
result to inspect the existing HR/role and leave RPC guards/locking. Complete
pending-account restrictions across remaining modules, transactional attendance,
private profile data isolation and secure attachment storage. The FCM webhook's
last supplied error remains 401; this migration does not repair remote push auth.
