#!/usr/bin/env python3
"""Single staging release for the supplied pre-004 schema; do not replay bundles."""
from build_phase1_bundle import ROOT, MIGRATIONS, build

if __name__ == '__main__':
    target = ROOT / 'supabase/deploy/core_hr_release.sql'
    text = build(MIGRATIONS + ['202611030007_leave_ranges_cancellation_history.sql'])
    target.write_text(text.replace('scripts/build_phase1_bundle.py', 'scripts/build_core_hr_bundle.py')
                      .replace('pre-004/005/006 schema snapshot', 'pre-004/005/006/007 schema snapshot'))
    print(target)
