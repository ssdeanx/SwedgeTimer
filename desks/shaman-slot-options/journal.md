# shaman-slot-options — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Wire the option widgets + defaults for the two new shaman HUD slot toggles the
  `shaman-slots` lane shipped (`hud_show_lightningshield`, `hud_show_searing`) — the options
  half of `bench/shaman_slots_2026-10-19.md` §2's filed row.
- **Scope:** `option_tables.lua` (two widgets only), `config_presets.lua` (two defaults only,
  `false`), `tests/options_load_state.lua` (pins only). OUT: `classes/shaman.lua`,
  `shaman_guide.lua`, `practice*.lua`, `config.lua`, `main.lua`, `diag.lua`, `compat.lua`,
  `hud.lua`, `bars.lua`, `run.sh`, TOCs, versions, README/CHANGELOG/docs, other classes,
  git, lint-config.
- **Consumer (live, cite it):** `classes/shaman.lua` — `ST.SHAMAN.HUD_SLOTS` declares
  `lightningshield` + `searing` (lines ~3339-3340); the provider
  `ST.SHAMAN.get_hud_state` reads `hud_db["hud_show_" .. slot.key] ~= true` → hidden
  (lines ~3497-3502). nil = off; the HUD itself hides only on `== false`, so the provider
  gate is the no-default-visible gate.
- **Design:** nil-safe (nil = off; the consumer gates on `== true`), defaults `false`
  (the druid Claw shape, `hud_show_claw = false`), no default-visible change.
- **Spec:** `bench/shaman_slots_2026-10-19.md` §2 ("the `hud_show_lightningshield` /
  `hud_show_searing` defaults + the options widgets" filed row) + the druid Claw reference
  shape in `option_tables.lua:5278-5281` / `config_presets.lua:294-297` /
  `tests/options_load_state.lua` §14 (D-1 pins).
- **Next step:** add the two slot toggles to the SHAMAN `hud_rotation_widgets` slot list
  (before the trinkets, mirroring `ST.SHAMAN.HUD_SLOTS` order), add the two `false`
  defaults to `ST.SHAMAN.defaults`, pin both in `tests/options_load_state.lua`
  (order/descriptor/getter/setter + defaults + consumer citation), then mutation-proof the
  pins on `/tmp/opencode` copies and run the full harness + luacheck.
- **Validation owner:** orchestrator.

## 2026-10-19 — the two maintain-mirror toggles wired, pinned and mutation-proved
- **Worked on:** the options half of `bench/shaman_slots_2026-10-19.md` §2's filed row.
  `option_tables.lua`: two slot toggles in the shaman section's shared
  `hud_rotation_widgets` builder — `hud_show_lightningshield` (8.47, line 5851) and
  `hud_show_searing` (8.48, line 5852) — placed between the rotation slots and the
  trinkets so the row mirrors `ST.SHAMAN.HUD_SLOTS`; plus ONE copy fix, the shaman glow
  description, which said "No other icon glows" and became false when the lane's two
  glowing mirrors landed (it now names them; flagged in the bench artifact, the orchestrator
  can revert it with its pin). `config_presets.lua`: `hud_show_lightningshield = false`
  (1064) and `hud_show_searing = false` (1065) in `ST.SHAMAN.defaults` — the druid Claw
  mirror's shape (nil = off, false = hidden, no default-visible change).
  `tests/options_load_state.lua`: new section 23 ("S-M1", 32 checks) — the toggle widget,
  its numeric order, name, desc, the resolved getter (true → true, nil → off), the
  resolved setter and its class-key write, the row order, the glow copy, both defaults
  (false + no true), and the live consumer (the two HUD_SLOTS descriptors — the find is
  scoped to that table, because the guide slots carry the same keys — plus the
  `hud_show_` read and the `~= true` gate at `classes/shaman.lua:3499`).
- **Current state:** `tests/options_load_state.lua` **3318 checks / 0 failed** (the
  baseline without §23 is 3286 / 0 — this lane adds 32). luacheck: my three files
  **0/0**; the repo total **2 warnings / 0 errors** = the standing floor. Mutations
  **13/13 killed, 0 void** on `/tmp/opencode/shaman-slot-opt-mut` copies (control green;
  the repo tree verified byte-identical to the pre-mutation snapshot). Bench artifact:
  `bench/shaman_slot_options_2026-10-19.md`. The harness reads **41 steps / 1 failed** —
  the one failure is **not** this lane's: `tests/shaman_guide_state.lua` → "the class
  module is reachable from the addon namespace (got nil)" — the HU-7 cleanup (the
  parallel lane removed the `st.SHAMAN = ST.SHAMAN` mirror from `classes/shaman.lua`;
  that suite still pins the old mirror; both files are other lanes'). **Proof of
  independence:** on `/tmp/opencode/sso-iso` (a copy of the repo) the harness fails
  identically WITH and WITHOUT this lane's three changes (41 steps / 1 failed, same
  message). Earlier in the window the red was the guard lane's `st.guard` nil in five
  sandboxes, then its `classes/shaman.lua` 200-local overflow (a hard `luac5.1 -p`
  error — its owner has since landed the fix); the failing set moved repeatedly with my
  three files untouched. No git, no lint-config, no out-of-scope file touched.
- **Next step:** orchestrator validates. Filed for the orchestrator (bench artifact §4):
  the two mirrors in `ST.SHAMAN.HUD_TEMPLATES` (a template pick WRITES the slot keys —
  out of this lane's brief), the `hud_state.lua` "ships false" pin (that file is another
  lane's; this lane's §23 carries the stricter equivalent), and the S-29 shield choice
  (unchanged from the slots lane).
- **Did not work:** the `hud_state.lua` "ships false" pin was wanted (the druid precedent
  at `tests/hud_state.lua:1222`) but that file is out of scope — the §23 pins are
  stronger anyway (false AND no-true). The 200-local overflow in `classes/shaman.lua`
  cannot be fixed from here at all; it needs the owning lane.

## 2026-10-19 — [signal:checkpoint] the deliverable is done; the harness is red from a sibling lane
- The two widgets + two false defaults + 32 pins are landed and mutation-proved; the
  options suite is green (3318 checks / 0 failed). The one harness failure is
  `tests/shaman_guide_state.lua` → "the class module is reachable from the addon
  namespace (got nil)" — the HU-7 cleanup (the parallel lane removed the
  `st.SHAMAN = ST.SHAMAN` mirror from `classes/shaman.lua`; that suite still pins it).
  Both files are other lanes'. **Independence proof:** the same `/tmp/opencode/sso-iso`
  copy fails identically with and without this lane's three changes.
  Earlier in the window the red was the guard lane's `st.guard` nil in five sandboxes,
  then its `classes/shaman.lua` 200-local overflow (a hard `luac5.1 -p` error; its owner
  has since landed the fix). Not a disagreement (no operator ruling needed): a crossfire
  blocker with a clear owner.
- Escalation: reason = crossfire blocker in sibling lanes' files; blocked_on = the
  shaman-drills/shaman-slots lane updating `tests/shaman_guide_state.lua` for the HU-7
  mirror removal; recommendation = this lane's deliverable can be validated as-is
  (options suite green, luacheck 0/0 on its three files, 13/13 mutations killed); do not
  merge on a red harness.
- desks/shaman-slot-options/.signals/20261019T223000Z.json

## 2026-10-19 — [signal:done] the two maintain-mirror toggles are wired, pinned and mutation-proved
- `hud_show_lightningshield` + `hud_show_searing` ship as toggle widgets (shaman section,
  shared `hud_rotation_widgets` builder) with `false` defaults; 32 new pins in
  `tests/options_load_state.lua` §23; options suite 3318 checks / 0 failed; luacheck 0/0
  on my three files; mutations 13/13 killed, 0 void. Bench artifact:
  `bench/shaman_slot_options_2026-10-19.md`. Validation owner: orchestrator.
- desks/shaman-slot-options/.signals/20261019T223000Z-done.json
