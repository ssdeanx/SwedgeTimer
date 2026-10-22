# hunter-utility-live — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Make the hunter's APL utility lines **live** — give every
  `live = false` row in `ST.HUNTER.PRACTICE_ROTATIONS` the read it needs (via
  the existing `compat.lua` wrappers only), so the frozen guide engine
  (`hunter_guide.lua`) can decide each line from live reads, the practice
  scenario can ask for it, and the guide can light it.
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua`, `hunter_ui.lua`,
  `practice_ui.lua` (the practice-strip geometry only), `tests/hunter_state.lua`,
  `tests/hunter_guide_state.lua`, `tests/practice_ui_state.lua` (the strip
  geometry pins only). Out of scope: `practice.lua`, `option_tables.lua`,
  `config_presets.lua`, other classes, `main.lua`, `diag.lua`, `compat.lua`,
  `hud.lua`, `bars.lua`, `run.sh`, TOCs, versions, docs. No git, no lint-config
  change.
- **Flags (HU-13, orchestrator ruling):** two flags, cross-class —
  `live` = the line's read exists and the line can be evaluated;
  `engine` = the frozen engine has an arm that can ask for it. Apply to the
  hunter's rows; flip both honestly.
- **Also in scope:** the practice strip's row height — the strip is a fixed
  74 px with 4 buttons per row (8 max) and the Wrath spine is 13 rows, so a
  third row spills out of the strip. Make the strip grow (or scroll) so no
  rotation row is unreachable, and pin the geometry.
- **Source of truth:** `bench/hunter_apl_utility_build_2026-10-20.md` (§6 names
  the read each filed row needs) and `bench/rotation_gap_vs_apl_2026-10-20.md`
  §2 (the hunter). Note the gap analysis's hunter section carries five errors,
  corrected in the bench file §5 — the bench file wins.
- **Next step:** read the gap file's hunter section + the shipped rotation table,
  the guide engine's arm shape and the practice strip's geometry; then wire the
  reads, add the engine arms, grow the strip, pin all of it, and prove the
  mutations on `/tmp/opencode` copies.

## 2026-10-20 — The utility lines went live
- **Worked on:** re-fetched all six hunter APL files from `wowsims/*/master`
  (the raw JSON, every group expanded) and took EVERY id, index and condition
  from them — the gap analysis is only the input. Wired the reads for all 18
  listed lines through the existing compat wrappers only (`api.GetSpellCooldown`,
  `api.scan_player_aura`, `api.scan_unit_aura`), added the engine arms at each
  family's APL position, flipped both flags per HU-13 (every row is live +
  engine-facing except the Forever Aimed Shot, which stays filed with its
  `needs`), grew the guide's slot sets to the families' whole spines, made the
  practice strip's growth explicit and pinned it. The Forever Steady Shot row
  is gone (the client has no Steady Shot).
- **Current state:** `tests/hunter_state.lua` PASS (1191),
  `tests/hunter_guide_state.lua` PASS (1860), `tests/practice_ui_state.lua`
  PASS (1401); luacheck 0/0 on the six touched files; 11/11 mutations killed
  (`python3 /tmp/opencode/mutations_hunter_utility.py`). Tree harness: 41
  steps, 2 failed — BOTH from the parallel warrior lane's crossfire (its own
  utility work is mid-flight), not from this lane. Artifact:
  `bench/hunter_utility_live_2026-10-20.md`.
- **Decisions worth the trail:** (a) the WotLK EXECUTE sits above the APL's
  Silencing Shot (the shipped research calls the execute "always highest when
  available" and it is a burst moment an interrupt must not shadow);
  (b) the "buff up -> never ask" rule wins over the ERA APL's
  `dotRemainingTime < 5 s` early refresh; (c) the melee rows read the weave
  band, the aspect swaps read the mana; (d) the scenario's default state
  ("every cooldown ready") means the family's TOP APL row now leads, so the
  offline verdicts moved (the WotLK -> the Silencing Shot, the Era -> the
  Rapid Fire) — the live scenario is unaffected (the live ctx carries the real
  cooldowns); (e) the hunter's own "six of the six allowed" guide-slot contract
  is GONE — the slot set now covers the family's whole APL spine (the frame
  has no cap; the shaman ships 18).
- **Dead ends:** the filed worry that the practice strip is a FIXED 74 px does
  not hold — `practice_row_set_height` already grows it with the button lines;
  the work there was to make it explicit and pin it. `practice_ui.lua` has 199
  file-scope locals (Lua 5.1's limit is 200), so no local could be added there.
- **Next step:** the orchestrator validates. Still filed for a follow-up lane:
  the Forever Aimed Shot's read (the gather's aimed block is Era-gated), the
  Explosive Trap's DOT id (the APL gates on `not dotIsActive(49067)`), the
  SoD Kill Shot's "Rapid Fire up" half (no RF aura read), and the Era Rapid
  Fire's narrow APL window (the arm uses the house "off cooldown" pattern).

## 2026-10-20 — [signal:done] The hunter's utility lines are live
- The APL utility layer is wired end to end: the reads, the engine's arms, the
  guide's slots, the honest flags and the practice strip's geometry.
- Signal: `desks/hunter-utility-live/.signals/2026-10-20T06-35-00Z.json`
  (`execution/done`, run id `hunter-utility-live-2026-10-20`).
