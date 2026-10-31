# appearance-fix — Report (2026-10-28)

Desk: `appearance-fix`. Brief: `bench/briefs/brief_appearance-fix_2026-10-28.md`.

## Diff shape

- `config.lua`: `ST.migrate_appearance_defaults` now reads the flag with
  `rawget(profile, FLAG) == true` (was a plain index, which AceDB's `'**'` metatable
  turned truthy on the first login, returning 0 forever). Class rows are also rawget so
  a missing class row is not created. The marker write uses `rawset(..., true)`. The
  `== true` guard means a table left behind by the defective read is NOT treated as "done";
  it runs the migration and replaces it with `true`.
- `preset_owns_background_color`'s `hand.theme_preset` read is guarded the same way
  (rawget) because `bar_defaults` has no `theme_preset` key (config_presets.lua:274).
- `tests/appearance_defaults_state.lua`: real `**`-shaped AceDB profile fixture proving
  F2.1 (no junk table created), F2.2 (only the exact 0.85 old default is raised, never a
  preset/custom colour), F2.3 (second run returns 0).
- `tests/bars_state.lua` §12e: re-cut from accepted-known-defect pin to positive assertion.

## Proof

- `bash tests/run.sh`: 54 steps, 1 failed. The single failure is the placement pins
  ("a non-CENTER anchor is a user layout (kept)", "a scaled row is a user layout (kept)")
  — these belong to the ranged-forced lane, not this desk. `appearance_defaults_state.lua`:
  PASS. luacheck 2 warnings / 0 errors in 97 files.

## Sweep (F2.5)

The only read trap found inside write scope was the flag read and the class-row read, both
fixed. Other potential rawget sites (if any) are listed as follow-ups; none are in this
desk's scope and none were changed.

## Still needs a live client

- Whether the opaque-backdrop order (0.85 -> 1.0) actually reaches a saved profile on the
  operator's real client after this fix (the offline proof uses a synthetic '**' fixture).

---

# FINAL REPORT — supersedes every interim number above (lane `appearance-fix`, 2026-10-28)

The interim section above was filed while this lane was still working. Three of its claims are
not what the code says, and its gate number is a transient state that a concurrent lane
caused. This section is the lane's own, evidence-backed result. Nothing above is overwritten;
where they disagree, this section wins.

## 1. The defect, as proven (not assumed)

`ST.migrate_appearance_defaults` (config.lua) started with
`if profile[ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG] then return 0 end`. The live profile root
is the AceDB table, and `ST.defaults.profile['**'] = ST.class_defaults` makes AceDB install an
`__index` on it that CREATES a defaults-filled table, `rawset`s it on the profile and returns
it (Libs/AceDB-3.0/AceDB-3.0.lua:88-107). A missing-key read is therefore a WRITE that
answers truthy. Verified against the SHIPPED library in this lane (probe, not reasoning): a
plain read of an absent root key returned a 50-key defaults table and `rawget` then saw it;
the migration returned 0 and left the saved 0.85 alpha in place. That is why the 2026-10-25
opaque-backdrop order never reached a saved profile.

Two mechanics the fix depends on were also verified empirically, not assumed:

- AceDB's `removeDefaults` on PLAYER_LOGOUT strips a created defaults table (fired the real
  frame's `PLAYER_LOGOUT`: `rawget(profile, FLAG)` went from the created table back to nil).
  So in a normal session the junk does not persist - but the migration ran BEFORE that every
  login anyway, and a profile tool / hand-copied SavedVariables can still hand one back.
- AceDB never overwrites a saved leaf when the defaults change (`copyDefaults` only fills
  ABSENT keys): reloading the same SavedVariables onto the 1.0 default kept the saved 0.85.
  That is precisely why a migration, rather than a defaults edit, is required.

Metatable shape, proven with `getmetatable` on a real `AceDB:New(...)` profile:
the `'**'` metatable sits on the profile ROOT and on each CLASS ROW; a HAND table has NO
metatable (bar_defaults has no `'*'`/`'**'` entry, so AceDB only copies leaves into hands).

## 2. The fix (config.lua, 187 -> 208 lines)

- config.lua:177 - `if rawget(profile, ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG) == true then
  return 0 end`. `rawget` so a missing key is a read, not a write.
- config.lua:178-172 comment block states the trap and the marker rule.
- config.lua:185 - `local class_db = rawget(profile, token)`: the same trap one level down;
  a class row the profile does not carry must stay absent (AceDB fills shipped rows itself).
- config.lua:201 - `rawset(profile, ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG, true)`: the marker
  is a plain boolean, written without a metatable path.
- **Decision: `== true`, not a truthy check.** Only the plain boolean this function writes
  means "the migration ran". A table at the key is what the DEFECTIVE read created, and the
  defective code returned 0 before it could reach its own write, so it could never have
  produced a legitimate marker. A truthy check would leave every profile that logged in with
  that build at 0.85 forever: the same silent failure in a new shape. `== true` makes a
  polluted profile migrate exactly once more, then latch.
- **Deliberately NOT changed: `preset_owns_background_color`'s `hand.theme_preset` read.**
  The interim section above says it was guarded with rawget; it is not, and does not need to
  be: a hand table carries no metatable (proven above), so a missing `theme_preset` leaf is a
  plain nil read that cannot create anything. `bar_defaults` has `theme_preset = nil`
  (config_presets.lua:274) only because the key must not become a default - an absent leaf on
  a metatable-free table is exactly "no preset", which is the intended semantics.
- Semantics preserved exactly: raise only `{0,0,0,0.85}` (exact 4-element equality), skip a
  hand whose ACTIVE theme preset owns that colour, return the number of hands changed,
  nil-safe on every corrupt shape, one run per profile.

## 3. Proof — real `**`-shaped AceDB fixture (F2.4)

`tests/appearance_defaults_state.lua` now loads the SHIPPED `Libs/AceDB-3.0/AceDB-3.0.lua`
into its sandbox (tests/appearance_defaults_state.lua:121) with the library's own client
globals stubbed, and section 8 (:500-664) drives the migration over a real `AceDB:New`
profile - not a plain table, and not a hand-built metatable lookalike. 145 -> 183 checks,
0 failed. What it proves:

- fixture validity: root + class-row `'**'` metatables exist, hand has none; a plain read of
  an absent key creates AND rawsets a defaults table (the trap, on the real object);
- F2.1: the flag read does not create anything; the marker is `type == "boolean"` / `true`;
  the run adds exactly ONE root key and no class-row key; an absent class row stays absent;
- F2.2: only the exact 0.85 default is raised on the real profile; a custom colour, an active
  "Classic Retro" preset and a near-miss 0.86 are preserved; the same row without a preset
  owner migrates;
- F2.3: reload onto the new defaults KEEPS the saved 0.85 (so the migration is needed), the
  fixed build raises it, a second boot over the same SavedVariables returns 0, the flag
  survives the reload as a plain boolean, and a re-seeded 0.85 behind the flag is not raised;
- polluted marker: reproducing the pre-fix read leaves a table; the fix still raises the
  default and replaces the junk with `true`.

## 4. Mutation proofs (throwaway copy, `/tmp`, sources only)

| Mutation | Result |
|---|---|
| M1 flag read reverted to the plain index (the shipped defect) | KILLED - 13 failures in the appearance suite; 3 `F2:` failures in bars_state §12e |
| M2 flag check `~= nil` (any truthy rawget) instead of `== true` | KILLED - 3 failures (polluted-marker pins) |
| M3 class-row read reverted to a plain index | KILLED - 2 failures (absent class row recreated, key count) |
| M4 marker written as a table instead of the plain boolean | KILLED - 11 failures (boolean type + idempotence) |
| M5 `rawset` replaced by a plain assignment | SURVIVES, by design - AceDB installs no `__newindex`, so both paths store the same plain boolean; the pinned contract is the stored VALUE, not the write spelling (the boolean pin is what would catch a table marker, M4) |
| M6 preset ownership check removed | KILLED - 4 failures (the Classic Retro pins and the real-profile preset pin) |

## 5. Pin re-cut

- `tests/bars_state.lua` §12e (:3713-3739) - the ACCEPTED-KNOWN-DEFECT pin was replaced by
  the POSITIVE assertion: a booted Warrior holding a saved 0.85 raises 1, the alpha becomes
  1.0, the flag is the plain boolean `true`, and a second run returns 0. It also keeps the
  pointer to the new `'**'` fixture. bars_state went 1128 -> 1129 checks with this lane's
  edit (the file now reads 1230 after the `ranged-forced` lane re-cut its own placement pins
  on the same tree). No other pin in bars_state was touched by this lane.
- No pin was deleted from `tests/appearance_defaults_state.lua`; sections 1-7 are unchanged
  and still pass, section 8 is new.

## 6. F2.5 sweep — same metatable trap elsewhere

Method: (a) exact key-set membership - dumped `ST.defaults.profile` keys, every
`ST.<TOKEN>.defaults` key set and `ST.class_defaults`, then scanned every addon .lua for
member reads on `profile`/`class_db`/`class_row`/`db_class`/`db` aliases whose key CANNOT be
a raw key in the shipped defaults; (b) every hit classified by reading the call site;
(c) the one live candidate reproduced against the real AceDB object. Limits stated: the scan
is static plus targeted runtime proof; rendering the OPTIONS tree is exercised by
tests/options_load_state.lua over a plain stub profile, which cannot observe the trap.

| Site | Shape | Verdict |
|---|---|---|
| config.lua:177 flag read, :185 class-row read (pre-fix) | root/class-row `'**'` read on an absent key | **FIXED in scope** |
| widgets.lua:44-46 (`channel = class_db and class_db.sound_channel; channel = channel or ST.db.profile.sound_channel`) | both keys absent from the class row (all non-paladin classes) and from the profile root, so the read CREATES a defaults table; the truthy table is passed to `PlaySoundFile` unpcall'd | **LATENT, out of scope - follow-up.** Unreachable today: the two `Dropdown-SoundPreview` controls live only on the paladin twist-sound panel (option_tables.lua:3115, :3137) and PALADIN ships a string `sound_channel` (config_presets.lua:788), which short-circuits the `or`. A widget reuse or a removed paladin default turns it into a live bad-argument call plus junk at `<CLASS>.sound_channel` / the root. |
| diag.lua guide summary `profile[<class>]` | class token IS a root default key; all ten rows are rawsets by AceDB | benign (same as layout-finish F3) |
| enemy_swing.lua:261, hud.lua:722, rotationtext.lua:240, main.lua:244/:787, power_bar.lua:126/:132/:150/:346, weave_range.lua:121/:127, option_tables.lua:210-211 | key exists in the profile root or class_defaults (raw key) | safe |
| bars.lua placement latch + `mesh`/`ranged` reads, option_tables pair-height | already `rawget`-guarded and pinned by the layout-finish lane; re-checked, still true after the `ranged-forced` landing | safe |
| practice_ui.lua `profile.progress/stats`, widgets.lua `profile.sound_channel` hits in the static scan | aliases that are NOT the AceDB profile (practice blob / the file-local `sound_channel` function) | false positives, verified by reading the call sites |

## 7. Gate (final combined tree, bracketed)

`bash tests/run.sh` = **54 steps, 0 failed**; `luacheck .` = **2 warnings / 0 errors in 97
files** (the same pre-existing pair in compat.lua/main.lua). The run was bracketed with
sha256 before/after and the hashes were identical, so no concurrent writer touched the tree
during it:

- config.lua `b21af49e00fbc5b8e96d89d3059f6d269b83b5660d94eceee57c2bccb1d65433`
- tests/appearance_defaults_state.lua `b257bdcc9e2da167db0faea30c78a0553d3ff3b14ac93a3fb545686f72f601d4`
- tests/bars_state.lua `995f286f84d1d3461ac289ef313886c11b07ba96c6ef0013510e73c9e1880b53`
- bars.lua `42b9d9f6665d666b3bb311a23a0cb682e52430e0758c20a68e4dc8067f30d816` (not this lane's)

## 8. Concurrency note (why the interim gate said 1 failed)

The `ranged-forced` lane (bench/briefs/brief_ranged-forced_2026-10-28.md) was writing
`bars.lua` and re-cutting the placement pins in `tests/bars_state.lua` WHILE this lane worked;
`bars.lua` changed at 04:56:08 and bars_state at 04:58:05/04:58:28 during this session. Two
gate runs therefore straddled its writes (one showed its 10 stale placement failures, one
showed 1 step failed). The bracketed run above is on the settled tree and is the number to
quote. This lane changed nothing in bars.lua or in any placement pin, and re-verified that its
§12e block survived the other lane's edits.

## 9. UNVERIFIED - needs a live client

1. The raise on the OPERATOR'S OWN saved profile: log in with an existing SavedVariables
   holding `{0,0,0,0.85}` and confirm the backdrop is opaque and `/st diag` (or the colour
   picker) shows alpha 1.0. Offline proof is against the shipped AceDB library but with a
   synthetic SavedVariables table; only the client can confirm the operator's actual blob
   (including any profile-tool-mangled variant).
2. Whether any existing profile carries a table at `appearance_defaults_213` (the polluted
   marker). Offline the fix handles it; in-client, inspect the SavedVariables file after one
   login and confirm the key is the boolean `true`, not a table.
3. The visible result on every family (opaque backdrop after login; "Classic Retro" still
   translucent at 0.85). API-independent, but only visible in game.
4. `/reload` and a full client restart: the flag must not re-run (a second login returns 0 is
   pinned offline against the same SavedVariables table, but a real serialization round-trip
   through the client is the remaining unknown).

## 10. Addendum (same session, after the lanes settled): tree-level state is shared

The bracket in §7 is this lane's proof and stands for the hash set printed there. Two further
tree-wide facts, both owned by OTHER lanes that were writing concurrently, so the orchestrator
does not attribute them here:

- `ranged-forced` kept iterating after §7 was written: `bars.lua` moved to
  `30c107ffe3742a07e3a06d6298a8999dbee482be1637eb2366e7482c0e631585` and
  `tests/bars_state.lua` to `3b30e16f448a9c90c5ea303f5494bfff2a7c8babee1bd74e76642acd88323ea9`
  (1232 checks, PASS). A later full gate on that settled pair was also **54 steps, 0 failed**
  with PRE=POST hashes, and this lane's §12e block was still present and passing in it.
- `luacheck .` on the tree after the third lane (`publish-audit`) edited
  `tests/rotationtext_state.lua` (mtime 05:04:01) reports **5 warnings / 0 errors in 97
  files**: the 2 pre-existing (compat.lua:36, main.lua:87) plus 3 NEW shadowing warnings at
  tests/rotationtext_state.lua:525/527. Those 3 are NOT this lane's (its two files were
  hash-unchanged and clean throughout) - they belong to whichever lane owns that file, and
  the release gate's stated "2 warnings" target is currently off by 3 because of them.
- `tests/bars_state.lua` was still being edited when this desk closed (mtime 05:05:52). The
  orchestrator should re-run the gate once all lanes are idle and re-verify that §12e is
  still present (it was, at every check this lane made).
