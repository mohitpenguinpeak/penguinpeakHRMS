# Permanent user deletion

Apply `supabase/migrations/202611130011_permanent_user_deletion.sql` after migration 010.
Deploy the server endpoint from this repository:

```sh
supabase functions deploy delete-user --no-verify-jwt --project-ref YOUR_PROJECT_REF
```

The endpoint validates the bearer token with Auth and requires an approved HR profile itself. The service-role key stays on the server (Supabase supplies its default service credentials). Never add it to Flutter defines.

HR opens Employees, chooses Delete user permanently, and confirms. Previously removed accounts are available through Previously removed. No existing accounts are deleted by installing the migration.

Deletion removes uploaded objects through the Storage API, then hard-deletes the Auth user. Database foreign keys remove owned records, including the profile, and dependent attendance, leave, messages and logs. Shared records retain other users' data while nullable attribution is cleared. An HR user cannot delete their own account. Direct reports must first be reassigned.

Storage and Auth are separate services: a later failure can leave files already removed while the account still exists. Errors do not report successful deletion; retry after checking server logs. Verify on a test account before production rollout: non-HR denied, self-deletion denied, direct reports blocked, profile and Auth identity removed, email can be registered again, remaining HR and other employees unaffected.
