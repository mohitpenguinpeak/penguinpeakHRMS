# Selected HR services — 4 November 2026

The new HR services are limited to **Onboarding**, **Payslips & Salary**,
**HR Helpdesk**, and **Document Centre**. Expenses, shifts/swaps, performance,
assets, offboarding, and reports/exports have been removed from the application.
Existing attendance, leave, tasks, chat and other original pages are unchanged.

## Backend setup

These source changes do not apply SQL to a live Supabase project.

- If the initial HR migration has not been installed, apply
  `supabase/migrations/202611040001_hr_modules.sql`, then
  `supabase/migrations/202611040002_limit_hr_modules.sql` in that order. The initial
  migration requires the existing migrations 004–008.
- If the initial HR migration is already installed, apply **only**
  `202611040002_limit_hr_modules.sql`.
- Do not replay previously applied migrations. The original HR migration is
  retained as deployment history. The follow-up migration restricts both reads
  and writes to the four selected modules, including attachment access. Older
  records and files for retired modules are preserved, not deleted. A NOT VALID
  check constraint permits their retention while rejecting new retired records.
- Keep `hr-private` Storage private. New buckets allow PDF/JPEG/PNG files up to
  10 MB; existing bucket settings are not overwritten. Check for pre-existing
  broad Storage policies that might grant access independently of these rules.

## Retained workflows

| Service | Behavior |
| --- | --- |
| Onboarding | HR creates a joining record with date and buddy/contact. Employee or HR saves the checklist and private joining documents. Completion requires all four saved checklist items. |
| Payslips & Salary | HR records monthly basic salary, allowances and deductions, uploads a payslip, and publishes it. Net salary is displayed. Drafts are private to HR; employees see only their own published payslips and downloads. One record per employee/month. |
| HR Helpdesk | Employees raise HR/IT/payroll tickets with category, priority and optional attachments. HR progresses and resolves tickets with a resolution note. Employees can close or reopen resolved tickets. |
| Document Centre | HR publishes private employee letters or company-wide policies with a version and attachment. Approved recipients acknowledge them once; HR can inspect acknowledgement names/timestamps. New versions are published as new records. |

Writes use authenticated RPCs and database authorization. Records retain
actor/timestamp history. Payslip support does not calculate statutory payroll or
transfer salary. File selection uses platform pickers; downloads use short-lived
signed URLs. Pages show up to 200 latest visible records.

## Android build

```bash
flutter build apk --release --dart-define-from-file=supabase.env.json
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.
The defines file is required by the app's startup configuration.

## Verification

```bash
flutter analyze
flutter test
node scripts/test_hr_modules.mjs /absolute/path/to/pglite/dist/index.js
```

The isolated PostgreSQL checks cover the retained workflows, private files,
publication/acknowledgements, and retirement of old module records without data
loss. They use minimal auth/profiles/Storage fixtures, not a live Supabase service.
Flutter checks cover the four modules at phone and desktop widths, including
forms with the keyboard open. Live database activation and physical-device file
picker acceptance remain separate deployment checks.

Latest local verification: 88 Flutter tests passed; 52 isolated SQL checks passed.
Analyzer reported no errors/warnings (108 existing informational findings). The
reduced Android release APK built successfully. No live migration was applied.
