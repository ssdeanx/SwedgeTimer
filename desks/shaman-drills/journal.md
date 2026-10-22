# shaman-drills — Journal

## 2026-10-19 — Desk opened
- **Purpose:** SHAMAN rotation scenario + the four target drills + the class-side
  feature-gap closure from `bench/class_features_drills_2026-10-19.md` §2.6.
- **Scope (fixed by the orchestrator):** `classes/shaman.lua`, `shaman_guide.lua`,
  `tests/shaman_state.lua`, `tests/shaman_guide_state.lua`. NOTHING else — no
  `practice.lua` / `practice_ui.lua` / `practice_progress*.lua` / `option_tables.lua` /
  `config*.lua` / other classes / `weave.lua` / `main.lua` / `diag.lua` / `compat.lua` /
  `hud.lua` / `bars.lua` / `run.sh` / TOCs / versions / README / CHANGELOG / docs.
  No git. No lint-config changes.
- **Interface contract (orchestrator-fixed, implemented verbatim):**
  1. `ST.SHAMAN.practice_rotation` — rotation table, sim priority order, each entry
     citing its sim source.
  2. `ST.SHAMAN.practice_scenario_step(self, ctx)` → `{ action, reason } | nil`
     (ctx = now / last_action / resources / cooldowns; nil = undecidable).
  3. `ST.SHAMAN.practice_drills` — `{ { key, label, grade = function(self, ctx) } }`,
     the audit's target drill set (§2.6 C: D-S1..D-S4).
  The shared engine registers the drills itself — this lane registers NOTHING.
- **Read first:** `bench/class_features_drills_2026-10-19.md` §2.6 (the spec with the
  sim citations), `desks/shaman-rotation-fix/journal.md` (the closure trail + the
  F1..F9 filed list), `bench/shaman_rotation_audit_2026-10-19.md`,
  `bench/lessons.md`, `bench/wrath_leftovers_2026-10-19.md`.
- **Baseline (this session):** full harness **41 steps / 0 failed**, luacheck
  **2 warnings / 0 errors** (the floor). Files are LF, no trailing whitespace;
  `classes/shaman.lua` indents with tabs, `shaman_guide.lua` with 4 spaces.
- **Next step:** implement the pure practice surface in `shaman_guide.lua`, the class
  contract in `classes/shaman.lua`, pin both suites, then mutation-prove on
  `/tmp/opencode` copies.

## 2026-10-19 — Shipped: rotation table + scenario step + 4 drills, 18/18 mutations
- **Worked on:** read the spec (`bench/class_features_drills_2026-10-19.md` §2.6) and
  the shipped shared engine (`practice.lua:3223-3477` — the class contract and the
  ROTATION_RUN_BANDS were already in the tree, so the hooks could be coded against
  them). Built the pure half in `shaman_guide.lua` (a new practice section; the
  frozen guide contract — 15 slots, the frozen input set, the rule order — is
  byte-identical) and the class half in `classes/shaman.lua`:
  `ST.SHAMAN.practice_rotation` (18 lines, sim priority order, every line citing its
  sim source, TBC name + Era id both shipped), `ST.SHAMAN.practice_scenario_step`
  (the engine's own verdict, nil when undecidable, the ctx family applied and
  restored), `ST.SHAMAN.practice_drills` (the audit's D-S1..D-S4: enh_priority,
  mw_weave on weave.lua's real marker/clip maths, stormstrike_hold, totem_upkeep).
  D-S4 consumes the Searing groundwork the audit lists unwired (the fight clock +
  the fire-slot reader, Era > 20 s / SoD > 30 s). The rotation table carries the
  Lightning Shield and Call of the Elements lines (live = false — no guide slot).
- **Current state:** `tests/shaman_guide_state.lua` 1 286 checks, `tests/shaman_state.lua`
  640 checks, both green; my four files luacheck 0/0; mutations **18/18 killed, 0
  void** on `/tmp/opencode/shaman-drills-mut/tree` (the repo tree never mutated —
  verified byte-identical). The full harness was **41 steps / 0 failed** with the
  repo luacheck at **2 warnings / 0 errors** (the floor) during the lane; it
  fluctuates afterwards only with the parallel hunter/rogue/engine lanes mid-edit
  (e.g. `classes/hunter.lua` calling a not-yet-defined `practice_family`,
  `practice_ui.lua` over Lua 5.1's 60-upvalue limit) — none of those suites load a
  shaman file, and this desk's two suites stay green throughout.
- **Filed:** the rest of §2.6 A with reasons in `bench/shaman_drills_2026-10-19.md`
  §2 (LS/CoE/Searing live slots need a 16th guide slot + the guide_contract/HUD/
  options lanes; the FE lineup needs the WoA id + a trinket-stack feed; the FS
  refresh default needs config/options; the CL sensor needs a compat probe; the
  twist buff-keyed re-drop needs an in-client id; S-23's Stormstrike fallback is
  never drawn — both consumers drop the full length when the ability is ready, so
  the fix is invisible until a consumer changes; S-24 autocast CDs, S-26 twist
  rank, S-27 Forever totems, S-29 shield choice filed as before).
- **Cross-lane (HU-7, hands-up.md):** the shipped engine resolves the class module
  from the addon NAMESPACE (`st[class_key]`) while the class tables live on the
  AceAddon table — so every class's scenario/drills are invisible to the engine.
  Class-side half done here (`st.SHAMAN = ST.SHAMAN` in classes/shaman.lua, pinned,
  engine integration proven through the shipped practice.lua); the central fix is
  the orchestrator's call.
- **Next step:** orchestrator validates (the in-client pass owns the unconfirmed ids:
  LS 49281, CoE 66842, Searing 10438, the FE 2894 / Magma 8190 / Lava Lash 60103 /
  Molten Blast 425339 / WF 8512+10614 / GoA 10627 family) and rules on HU-7.

## 2026-10-20 — [signal:done] shaman rotation scenario + drills + gap closure
- `practice_rotation` (18 sim-cited lines) + `practice_scenario_step` + 4 drills,
  1 926 pins across the two suites, 18/18 mutations kill, harness green for my
  scope; the class-side feature gaps closed on the practice surface and the rest
  filed with reasons (`bench/shaman_drills_2026-10-19.md`); HU-7 raised for the
  engine's class-module lookup. Validation owner: orchestrator.
- desks/shaman-drills/.signals/20261020T005435Z.json
