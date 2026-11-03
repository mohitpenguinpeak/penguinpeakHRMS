#!/usr/bin/env python3
"""Generate one atomic release for the last supplied pre-004 schema snapshot."""
from build_phase1_bundle import ROOT, MIGRATIONS, build

if __name__ == '__main__':
    files = MIGRATIONS + [
        '202611030007_leave_ranges_cancellation_history.sql',
        '202611030008_session_access_and_employee_capacity.sql',
    ]
    target = ROOT / 'supabase/deploy/stability_release.sql'
    target.write_text(build(files).replace('scripts/build_phase1_bundle.py', 'scripts/build_stability_bundle.py')
                      .replace('pre-004/005/006 schema snapshot', 'pre-004 through pre-008 schema snapshot'))
    print(target)
