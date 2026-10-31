# Brief — appearance-fix (2026-10-28)

Desk: `appearance-fix`. One proven defect, found by the `layout-finish` lane and confirmed
by the orchestrator by reading the code.

## The defect (F2)

`ST.migrate_appearance_defaults` (config.lua:158-187) can NEVER run on a live profile.
`config.lua:162` reads `profile[ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG]` directly. The
profile root is an AceDB table carrying the `'**'` defaults metatable
(`Libs/AceDB-3.0/AceDB-3.0.lua:88-107`), which CREATES and rawsets a defaults table on any
missing-key read and returns it. The read is therefore always truthy, the function returns
0 immediately, and the 2026-10-25 opaque-backdrop order (background alpha 0.85 -> 1.0)
never reached a single saved profile — silently, for a release.

## Write scope

- `config.lua`
- `tests/appearance_defaults_state.lua`
- `tests/bars_state.lua` — ONLY the accepted-known-defect pin from the layout-finish lane
  (§12e, the one that runs the real migration against a real AceDB profile and currently
  records the defect as accepted). Delete or invert it once the fix is in.

Do NOT touch anything else. Do not bump the version (stays 2.1.3). No git, no TOC/Libs
edits, no lint-config changes.

## Required outcomes

F2.1 The migration decision reads the flag without triggering the metatable (e.g.
`rawget(profile, FLAG)`), and the flag write still stores a plain value (verify how the
flag is written; it must not create a table either).
F2.2 The migration still does exactly what the 2026-10-25 order says: raise ONLY the exact
untouched old default (0.85) on each hand of each class row, never a preset-owned or
custom colour, and return the number of hands changed.
F2.3 It runs once and only once per profile: a second run returns 0.
F2.4 A real `**`-shaped fixture in `tests/appearance_defaults_state.lua` proves F2.1-F2.3
against a real AceDB profile object, not a plain table. `tests/bars_state.lua`'s §12e
accepted-defect pin is replaced by the positive assertion (or removed with a comment
pointing at the new fixture).
F2.5 Sweep the tree for OTHER reads of possibly-missing AceDB keys that rely on a plain
read for a boolean decision (the same metatable trap) and report them. Fix only the ones
inside your write scope; list the rest in the report as follow-ups.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `appearance-fix`),
  `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it.
- `bash tests/run.sh` must stay green (54 steps, 0 failed; luacheck 2 warnings / 0 errors
  in 97 files). List every pin you re-cut and why.
- Report to `bench/appearance_fix_2026-10-28.md`: the diff shape, the proof, the sweep
  result, and what still needs a live client.
