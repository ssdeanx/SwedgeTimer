# Final Gate Fixes — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the final publish-gate deep audit's HIGH-3 (the file-scope
  local ceiling) and the three MEDIUMs that ride the same three class files:
  MEDIUM-1 (the shaman's flat publish is never widened onto the panel),
  MEDIUM-2 (the paladin's flat publish carries the removed Seal of the
  Crusader on the 4.0+ clients) and MEDIUM-3 (two shipped comments contradict
  the code they describe).
- **Scope:** `classes/paladin.lua`, `classes/warrior.lua`, `classes/shaman.lua`,
  `tests/paladin_state.lua`, `tests/warrior_state.lua`, `tests/shaman_state.lua`,
  `tests/toc_check.lua` (the local-ceiling guard only). No other addon file, no
  TOC, no version, no CHANGELOG/README/docs, no git.
- **Source:** `bench/final_gate_audit_2026-10-20.md` (session
  `ses_ea50b69a7ffeT9t274D7oLIr6m`; HIGH-1/HIGH-2 belong to a sibling lane).
- **Next step:** the orchestrator validates.

## 2026-10-20 — HIGH-3 closed: the local ceiling is real headroom now
- **Worked on:** the three class modules sat at Lua 5.1's 200-local chunk
  ceiling - the paladin at **200** and the warrior at **200** (zero headroom:
  one more file-scope `local` would be a LOAD FAILURE on every client, not a
  test failure), the shaman at **199**. Their display constants now ride the
  module table (the classes' own precedent: `APL_UTILITY`,
  `practice_action_meta`, `practice_apl_rows`, `practice_prepull_rows`,
  `WARRIOR_UTILITY`): `ST.PALADIN.aow_pulse` / `.twist_colors` / `.twist_glow`,
  `ST.WARRIOR.hud_style` / `.bar_style` / `.HUD_COOLDOWN_FALLBACK` /
  `.HUD_SKIP_GCD`, `ST.SHAMAN.flame_shock_style` / `.stormstrike_style` /
  `.shield_style` / `.position_style` - **54 file-scope locals moved, every
  value byte-identical** (proved by the literal-by-literal comparison and by
  the new style pins in the three class suites).
- **The counts now:** the paladin **185** (15 free), the warrior **181** (19
  free), the shaman **179** (21 free) - the compiler's own number
  (`luac5.1 -l -l`), the same metric the audit measured.
- **The guard:** `tests/toc_check.lua` (an already-registered step - no new
  registry line) now counts every addon module's file-scope locals and fails
  above **190**, with the file, the count and the headroom in the message. The
  count is the compiler's own, so it counts NAMES (a `local a, b` line is two
  locals - demonstrated: one such line moved a file from 183 to 185), it
  includes the locals of a file-scope block and it excludes a nested
  function's own. `practice_ui.lua` (199, at the ceiling) is not this lane's
  file to change: it carries a BASELINE of 199 - a ratchet (it may shrink,
  never grow); every other file is held to the 190 limit.
- **Current state:** harness **43 steps / 0 failed**; luacheck **2 warnings /
  0 errors in 85 files** (the standing floor - the one new warning this lane
  briefly added was wired, not silenced).
- **Next step:** the orchestrator validates.

## 2026-10-20 — MEDIUM-1 closed: the shaman's panel widens on every family
- **Worked on:** `classes/shaman.lua`'s `apply_family_slots` returns BEFORE the
  widening on a family the class carries no rotation row for (the Cata and the
  Mists clients), so the five common abilities the class publishes as neutral
  there never reached the panel. `ST.SHAMAN.post_init` now calls
  `ST.SHAMAN.apply_practice_panel_actions()` itself - the other five class
  modules' pattern - so the widening runs on every family (the call is
  idempotent: a strip that already carries a common slot is left alone).
- **The pins:** the shaman's sandbox now answers the five common abilities'
  names (a client that has the spell does), which makes the widening
  observable end to end: two pins that were GREEN-BUT-WRONG (the strip's
  published list and the TBC slot count - the real client has always carried
  the common slots there) now state the truth, and a new pin proves the
  widening on a family with NO rotation row (the Cata client).
- **Current state:** harness green; the shaman suite **1064 checks**.
- **Next step:** the orchestrator validates.

## 2026-10-20 — MEDIUM-2 closed: the paladin's publish is family-scoped
- **Worked on:** `ST.PALADIN.practice_neutral_actions` is now ONE BUCKET PER
  FAMILY - ERA, TBC, WRATH and FOREVER keep the seal (it exists there),
  CATA, MISTS and RETAIL publish the same ten keys WITHOUT the Seal of the
  Crusader (removed in 4.0). The classic line is therefore UNCHANGED (a
  SoD build rides the Era bucket, as before); the only behaviour change is on
  the 4.0+ clients, where a `sotc` press is a mis-pick instead of a silent
  neutral press - the same treatment the rogue's 4.0-removed Shiv already
  gets. The offer gate needed no change: it reads the published set.
- **The pins:** the paladin's own suite (which now owns the publish's pin -
  `tests/neutral_actions_state.lua` says so at its header) checks every
  family's bucket, the seal's presence per family and the ten shared keys.
- **Note:** the sibling lane's `tests/neutral_actions_state.lua` already
  carried the post-fix expectation (the Cata/Mists/Retail slices without
  `sotc`, `sotc` as an intentional mis-pick) - the suite was green on the
  first run of this lane's change, so no out-of-scope test edit was needed.
- **Current state:** harness green; the paladin suite **1234 checks**.
- **Next step:** the orchestrator validates.

## 2026-10-20 — MEDIUM-3 closed: the two comments are true again
- **Worked on:** `classes/warrior.lua`'s ability-list note claimed the common
  abilities "have NO key in the warrior's own ability list" while the class
  publishes exactly those keys - it now states the truth (they have no key in
  the ROTATION and GUIDE vocabulary, and they DO have one in the class's own
  PRACTICE-PANEL ability list, where the publish offers them per family; the
  Defensive Stance and the Stoneform still carry no key anywhere). The
  resolver note's "every client family answers its own rank art" is FALSE (the
  fallback hands the ERA corpus's rank-1 id, and the classic-line name leg is
  UNCONFIRMED in-client - audit §6 C1) - the three in-scope class modules now
  say what the code does.
- **The pins:** three source-shape pins on the ABSENCE of the stale phrases
  (a correct rewording still passes) and one on the presence of the corrected
  statement.
- **Out of scope, filed:** the hunter, the druid and the rogue carry the same
  false "rank art" claim - they are not this lane's files.
- **Current state:** harness green; the warrior suite **2046 checks**.
- **Next step:** the orchestrator validates.

## 2026-10-20 — [signal:done] HIGH-3 + MEDIUM-1/2/3 closed, harness green
- `desks/final-gate-fixes/.signals/2026-10-20T223500Z.json`; the evidence is
  `bench/final_gate_fixes_2026-10-20.md` (the counts, the value-equivalence
  proof, the nine mutation kills and the two out-of-scope filings).
- Harness **43 steps / 0 failed**; luacheck **2 warnings / 0 errors in 85
  files** (the standing floor). The paladin **185**, the warrior **181**, the
  shaman **179** file-scope locals (the ceiling is 200); the guard holds every
  other module to 190 and `practice_ui.lua` to its 199 baseline.
