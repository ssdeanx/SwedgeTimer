# swing-harness desk journal

## 2026-10-22 — dispatched (swing cross-client legs)

- Worked on: read the brief (Pins 1-3), bench/proctor_swing_gap_2026-10-22.md,
  hands-up.md HU-25/HU-28/HU-29/HU-30, desks/journal.md lane table,
  swing_source.lua, tests/real_wire_state.lua, tests/swing_source_state.lua,
  the real vendored lib driver table (lib:42-47, 113-208, 383-537, 578-606,
  660-784), main.lua dispatcher (line 964+) + engine select (line 12-50) +
  event regs (line 585-652), compat.lua family mapping.
- Current state: probe verdict (lib-only sandbox, /tmp/opencode/probe_succeeded.lua)
  — lone SUCCEEDED(75) with NO prior START_AUTOREPEAT_SPELL drives ranged START
  on BOTH Era and anniv(1). The brief's Pin-1 (b) premise ("without prior
  autorepeat does not advance") is FALSE against the real lib (lib:600-606 has
  no isShooting gate and no family gate). Pinning (b)-as-stated would go red and
  stay red. Writing (b) as the true agreement leg instead (lone SUCCEEDED
  advances identically on both families — a gate added to the SUCCEEDED path
  breaks it); the family-DIVERGENT negatives are CAST_START (lib:456, isClassic
  gate) and FAILED_QUIET (lib:772, isClassic gate). No swing_source.lua change:
  no defect found there; the Forever joint gets its end-to-end leg through the
  real v7 + real dispatcher with zero product-code edits.
- Next step: edit tests/real_wire_state.lua (two-speed UnitAttackSpeed fixture,
  forever profile loading the REAL swing_source.lua through the REAL shipped v7
  into the REAL main.lua dispatcher; legs: TBC driver table, mh+oh
  START→UPDATE→hand-only STOP lifecycle, MISSED routing PASS, PARRY/EXTRA
  xfail, Forever joint), run both suites + luacheck, mutation-prove on
  /tmp/opencode copies, file done/blocked signal, report.

## 2026-10-22 — done (legs landed, suite green, mutations kill)

- Landed: tests/real_wire_state.lua only (no product-code edits; swing_source.lua
  needed none — no defect found there). Sandbox: two-speed UnitAttackSpeed via
  sb.attack_speed (default {2.6, 0} preserves the old shape); forever profile
  (project 18 / interface 16001, WOW_PROJECT_CAMELOT=18, Enum table) loads the
  REAL swing_source.lua after compat and captures its real v7 registry via a
  sandbox-local CBH-New wrapper; CombatLogGetCurrentEventInfo uses explicit
  maxn length (bare unpack truncates the 22-wide oh-damage tuple at nil holes).
  New legs: TBC driver table (lone-SUCCEEDED agreement both families;
  CAST_START Era-UPDATE/TBC-untouched; FAILED_QUIET Era-0.5s-window/
  TBC-untouched), Era mh START→STOP→full + oh START→UPDATE→STOP→full (first
  real-registry STOP coverage), MISSED main/oh routing PASS, PARRY + EXTRA
  xfail (HU-29), Forever joint (idle nil-shape seed, mh START→UPDATE→STOP→
  full, oh START→STOP→full, six regs in the source registry by identity).
- Results: real_wire_state 281 checks, 0 failures (3 xfail: PARRY, EXTRA,
  D2-anniv-nil); swing_source_state PASS (149 checks, untouched file, still
  green); luacheck 0/0 on the touched file. Mutations M1-M7 on /tmp/opencode
  copies all kill exactly their target legs (CAST_START gate swap: 2;
  SUCCEEDED Era-gate: 5 incl. the pre-existing anniv happy leg; FAILED_QUIET
  gate drop: 2; MISSED oh-forced-main: 2; dispatcher STOP-eater: 11 across both
  engines; Forever START arg swap: 6; DAMAGE oh-forced-nil: 3). Copy restored
  green, then deleted.
- Crossfire note: swing_source.lua (+75/-6, B1 nil-shape + unit filter +
  WEAPON_SLOT_CHANGED) and tests/swing_source_state.lua (+139) changed under
  this lane from the parallel build/fix lanes; the new legs pass against the
  landed version (the B1 nil-shape is exactly what the Forever seed asserts).
  Tree is shared with running lanes — orchestrator re-runs the full run.sh.
- Next step: none for this desk (validation owner: orchestrator). UNVERIFIED
  (needs in-client evidence, cannot be pinned offline): U2 (Anniversary
  expansion-level ground truth — decides whether D2's xfail is permanent),
  U3 (SUCCEEDED(75) delivery + UnitRangedDamage shape on 2.5.6),
  U-H5 (Forever in-client swing proof).

## 2026-10-22 — HU-31 ruling (Titanforge + Retail-silent)

- Worked on: applied the operator's HU-31 scope ruling to tests/real_wire_state.lua
  only (no product-code edits). Found the previous lane's legs intact except the
  file's top header comment, which had been reverted to the original text by an
  unknown hand - rewrote it per HU-31. Added: titan profile (project 11,
  expansion 2, interface 38002 - Titanforge-shaped, unblocks old U-W1) +
  titan happy leg; TBC/Wrath driver loops (agreement + CAST_START + FAILED_QUIET)
  extended to era/anniv/titan with Wrath-true negatives; lifecycle looped over
  era/anniv (shared body) + a separate Wrath-true life-tf leg (Wrath re-fires
  ranged on every melee swing, lib:405-413, so Era-shaped wire-last asserts do
  not hold there); MISSED looped x3; PX xfail kept Era-only (dead arms are
  family-independent); new Retail silent leg (no engine loads: inert stand-in
  ready, one unavailable notice, all hands engine_dead, zero wire traffic
  across the deadline). Sandbox fixes: manual clock now iterates to the append
  high-water mark (Lua 5.1 # is undefined on holed tables - a consumed timer's
  hole stranded Titanforge's re-fired ranged timer); CombatLog unpack keeps its
  explicit maxn length; retail notice-text assert is nil-safe (a missing notice
  FAILs instead of aborting the suite).
- Current state: real_wire_state 482 checks, 0 failures (3 xfail: PARRY, EXTRA,
  D2); swing_source_state PASS (149, untouched); luacheck 0/0. Mutations on
  /tmp/opencode copies: M8 Wrath-gate break -> 11 titan fails; M9 notice removal
  (copy-only main.lua) -> 3 retail + 2 D8 collateral, fails clean; M10 Wrath
  re-fire removal -> 6 quirk fails; M5 STOP-eater re-proved after the clock fix
  -> 26 fails. Copies restored green then deleted.
- Crossfire note: main.lua (+157) and swing_source.lua (+75) changed under this
  lane from parallel lanes; the new legs pass against the landed versions.
  Full run.sh re-verification is the orchestrator's.
- Next step: none for this desk. UNVERIFIED (in-client closers): U2 (anniv
  expansion-level ground truth - decides D2 permanence), U3 (2.5.6 SUCCEEDED +
  UnitRangedDamage shape), U-H5 (Forever live swing proof).
