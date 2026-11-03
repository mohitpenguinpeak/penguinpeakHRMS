# Organization chart layout correction

The old hierarchy rendered independent roots in a vertical Column, without
connectors. That made unrelated employees resemble one reporting chain and left
much of the desktop workspace unused. The renderer also silently chose an
arbitrary employee as root when the data had no valid roots.

The dashboard now reuses its existing authorized profile records through a
feature-specific OrganizationTree model and OrganizationChart widget:

- Independent roots share the top row; actual manager/report links have connectors.
- Desktop canvas fills available width, fits the forest initially and on filtering
  or resize, and supports pan, zoom, Fit to view and 100% reset.
- Phones default to an expandable outline; either view can be selected explicitly.
  Outline indentation is bounded for deep organizations and expansion keys remain
  separate from saved workspace scroll state.
- Search and department filters retain reporting managers as context. Search opens
  paths to matching descendants. Clicking a chart card, outline leaf or manager
  avatar opens the existing employee profile workflow.
- Missing/unavailable managers remain separate labelled roots. Cyclic links are
  flagged and excluded from drawing; each affected employee and their valid
  descendants remain reachable. No arbitrary manager assignment is invented.
- Approved profiles only, honest missing-field labels, original palette, responsive
  controls and card heights that account for text scaling.

This is a presentation/model correction. No profile data, manager assignment,
database policy, migration, dependency or environment setting is changed. Server
validation preventing invalid future manager assignments remains separate work.
An unavailable manager may be absent due to directory permissions or approval;
the UI does not assert that such a manager does not exist in the database.

Tests: 66 Flutter tests pass. New coverage checks multiple roots, correct parent
links, unavailable managers, approval filtering, cycles/self-management, descendant
search/context, profile opening, empty state, 320px outline and 768/1600px canvas
with 1.5x text. Temporary real-font phone/desktop renders were visually inspected
and preview-only fixture tests removed. Actual backend/device acceptance is not
claimed from these fixture tests.
