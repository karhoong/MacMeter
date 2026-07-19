# MacMeter 1.0.2 design QA

final result: passed

## Target and comparison

- Source: the owner-provided 1.0.1 popover screenshot showing weak grouping, limited spacing, sparse iconography, and a partially obscured first CPU row.
- Candidate: native AppKit light/dark bitmap captures generated from the production popover and every Settings tab at their real 390×520 and 560×430 content sizes.
- Comparison: the source and latest dark popover capture were normalized to the same height and reviewed side by side after the second layout pass.

## Resolved findings

- **Hierarchy:** metric sections now use consistent icon-led card headers and semibold titles.
- **Spacing:** 16-point outer padding, 14-point inter-card spacing, and consistent internal card padding replace the uneven grouping in the source.
- **Scanability:** numeric values remain right-aligned; network direction and battery state retain established colors; CPU and temperature now progress continuously from green through yellow/orange to red.
- **Settings:** every tab uses the same card language, outline SF Symbols, aligned controls, and a full-width layout. The About tab uses the real application icon in the built app.
- **Window identity:** the controller and window both explicitly own `MacMeter Settings`, and repeated show/tab-switch regression coverage prevents `Untitled` from returning.
- **Menu layout:** every multi-metric Compact selection produces exactly two rows; Network owns the top row when enabled, and the specified CPU/temperature/battery rules apply otherwise.
- **Accessibility:** color supplements existing values and spoken labels; it does not replace the visible CPU percentage, temperature, network direction, battery `C`/`D`, or VoiceOver text.

## Remaining polish

- No P0, P1, or P2 design issue remains in the rendered matrices.
- Physical menu-bar readability and the system VoiceOver traversal remain manual checks on the running Release app.
