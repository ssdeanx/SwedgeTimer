# Druid Wolfshead — Journal

## 2026-10-19 — Desk opened
- **Purpose:** build spec **BS-2** of `bench/filed_closure_sweep_2026-10-19.md` §7 — the druid
  **Wolfshead Helm** probe (item id 8345) as a reserved plug-in point in the guide inputs.
- **Scope:** `classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
  `tests/druid_guide_state.lua`. Nothing else. No git, no lint-config change, no TOCs, no
  versions, no practice/options files.
- **Enabler:** BS-1 has landed — `compat.lua` carries `api.is_item_equipped(item_id)`
  (true / false / nil) and `api.scan_unit_aura(unit, predicate)`. `compat.lua` is OUT OF SCOPE
  for this lane.
- **Key facts (sourced in the bench sweep):**
  - The sim's check is `HasItemEquipped(8345)` (the tbc-new feralcat rotation,
    `bench/class_features_drills_2026-10-19.md` §2.5); 8345 is the wowhead-confirmed
    **Wolfshead Helm** (`bench/ids_research_2026-10-19.md` §2).
  - The read path exists client-side: `GetInventoryItemID("player", slot)` in the client's own
    FrameXML on every branch, `INVSLOT_HEAD = 1` in `Constants.lua`
    (`bench/filed_closure_sweep_2026-10-19.md` §3 U-03).
  - The **Furor** half of the powershift basis is still unproven (DU-16: no published Furor
    talent id, no knowledge-proof talent read) → the SHIFT rule stays removed.
- **Build shape:** the gather publishes `inputs.wolfshead_equipped` (tri-state, nil-safe); the
  engine documents it as RESERVED; **no rule reads it**. It is a plug-in point exactly like
  `can_powershift` is today.
- **Rules:** nil-safe; unknown-hides (nil ≠ false); no default-visible change (no rule consumes
  the input); line endings preserved (`classes/druid.lua` + `druid_guide.lua` are CRLF, the two
  test files are LF); touched-lines whitespace only; mutation proofs on `/tmp/opencode` copies
  (a "false→nil" mutant and a "rule consumes it" mutant must each fail a pin).
- **Next step:** implement the gather input + the engine input spec, update the two suites, run
  the harness, prove the mutations.

## 2026-10-19 — [signal:done] BS-2 built, pinned, mutation-proven
- **Worked on:** the gather now publishes `inputs.wolfshead_equipped = api.is_item_equipped(8345)`
  (`classes/druid.lua:1907-1916`) and the stale "no honest probe exists" comments were replaced
  by the sourced two-probe position (`:1873-1885`, header `:22-25`). The engine's input spec
  names the input as RESERVED (`druid_guide.lua:73-89`) and the TBC / ERA / SOD REMOVED notes
  now say the Helm half has a probe while the **Furor** half does not (`:199-212`, `:290-295`,
  `:382-386`, `:896-900`). The name also rides the practice input vocabulary, like the other
  reserved inputs (`classes/druid.lua:2944`).
- **Tri-state kept (the spec's `or nil` was NOT copied):** the spec's literal
  `api.is_item_equipped(8345) or nil` would have collapsed the proven **false** into nil
  (`false or nil` is nil in Lua) and thrown away the only readable answer. The operator's brief
  says keep the tri-state, so the probe's answer is written as it is: true = worn, false = the
  read worked and no slot holds it, nil = unknown (never false).
- **Current state:** `tests/druid_state.lua` §38 pins the tri-state (true / false / nil / nil /
  the queried id 8345 / the stale-cleared reuse) against the **real** compat probe; the fixture
  needed `with_equipment_range(...)` because compat reads `INVSLOT_*` through `rawget(_G, …)` at
  **call** time. `tests/druid_guide_state.lua` gained the "no rule consumes it" pair: a
  behavioural pin (six representative inputs, action/hold/hold_text identical with the input set
  to true and to false) and a static pin (the source may name the input in a comment, never in
  code). Harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** (the floor); the
  four touched files are luacheck-clean on their own.
- **Mutation proofs** (`/tmp/opencode/bs2_mutations.py`, re-runnable): **A** false→nil → the
  druid_state false pin FAILS; **C** input not published → the druid_state true/id/false pins
  FAIL; **B** rule consumes it (a re-added TBC SHIFT hold) → the guide_state behavioural **and**
  static pins FAIL. Control copy green.
- **Not built, filed:** the SHIFT rule stays removed (DU-16 — the Furor refund basis is
  unproven: no published talent id, and `main.lua`'s `talent_positions` covers WRATH only, so a
  `GetTalentInfo` read on TBC would be a guess); the in-client confirm of 8345 is the
  operator's session; and the probe walks all 19 equipped slots on every gather (~380 reads/s at
  the guide's 0.05 s tick) — harmless while nothing consumes it, but a consuming rule will
  probably want a throttled read. That freshness change is a design decision for whoever wires
  the rule, so it was not taken here.
- **Caution for the orchestrator:** the `hunter-serpent` (BS-3), `shaman-coe-fs-ss` (BS-4),
  `paladin-forever-ids` (BS-5) and `options-pass` (BS-7) lanes were writing in the same
  tree during this session. The whole-tree harness was **41/0 at 23:11 and 23:19**; a later
  run (23:21) showed 10 red steps, every one of them in those lanes' files (the
  `luac5.1 -p` step trips on `classes/shaman.lua:3580` "more than 200 local variables",
  the shaman lane's in-flight edit). This lane's two suites were green in every run and
  its four files are `luac5.1 -p` + luacheck clean on their own. **Re-run the whole-tree
  validation once the concurrent lanes land.**
- **Artifact:** `bench/buildout_druid_bs2_2026-10-19.md` (new bench file; no existing bench file
  was overwritten).
- **Next step:** the operator validates in-tree; the next lane that wants the SHIFT rule must
  first land a **Furor** knowledge-proof talent read (BS-level: the open half of DU-16) and may
  then consume `wolfshead_equipped` — the "no rule consumes it" pin in
  `tests/druid_guide_state.lua` is the gate that has to be retired deliberately.
