# Hunter SoD Build — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the residual filed in `bench/hunter_hud_family_2026-10-20.md` §7.2 —
  the hunter's HUD dead-slot filter is family-blind, so the **SoD build of the Era client
  loses the Bestial Wrath slot it actually has**. The filter must become **build-aware**
  (Era-base vs SoD on the same 1.15.9 client), the SoD slot must carry the SoD client's
  own id through the existing per-family owner (`SPELL_ID_BY_FAMILY`,
  `classes/hunter.lua:130` + the runtime re-point at `:2212`), the guide must agree with
  the HUD, and the **Mists Raptor rank** (CLIENT-UNCONFIRMED in the lane's table) must be
  sourced or the slot filtered for that family with the reason recorded.
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua` (the frozen-spec display-slot block
  only), `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`, `tests/hud_state.lua`
  (**the hunter census only**). No git, no lint config, no other class, no docs/TOC/
  version, no `practice*.lua`, `option_tables.lua`, `config_presets.lua`, `main.lua`,
  `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `guide_contract.lua`, `run.sh`.
- **Constraints carried in:** the class's existing SoD detection only (the Chimera Shot
  rune 409433 — no new client read); unknown-hides (a slot whose spell cannot be
  resolved on the running build is never offered); every id cited; CRLF preserved in
  `classes/hunter.lua` / `hunter_guide.lua`; mutation proofs on `/tmp/opencode` copies;
  validation owner is the orchestrator.
- **Evidence gathered this session (all recorded in the bench report):**
  * **LOCAL, the operator's own Classic 1.15 client dump** (`/home/sam/wow.export`, the
    CSV export of the 1.15.9 client): it carries the SoD-only runes 409433 (Chimera
    Shot), 437123 (the SoD Steady Shot rune), 458482 (Wyvern Strike) and 409593 (the
    SoD Kill Shot), so it IS the SoD client. It carries **19574** (`Spell.csv:7657`)
    and maps it to **skill line 50 = Beast Mastery** (`SkillLineAbility.csv:3723`) —
    the SoD client HAS the Bestial Wrath. It does **NOT** carry 56641 (the TBC Steady
    Shot) or 34026 (Kill Command) → the Era pick's steady/kill_command drops are right.
    It carries the Era ranks the table cites: 14266 (Raptor), 25294 (Multi), 20904
    (Aimed), 3045 (Rapid Fire).
  * **warcraftdb's per-expansion domains are each client's own spell table** (WEB-
    CONFIRMED): `classic/…/2973` = "Raptor Strike - WoW Classic", `tbc/…/27014`,
    `wotlk/…/48996`, `cata/…/2973`, `forever/…/14266`, `warcraftdb/…/186270` (retail) —
    but `mop/…` answers **Not Found** for 2973, 14260..14266, 27014, 48995 and 48996.
  * The **wowsims repo the lane cited is gone** (`github.com/wago-io/wowsims` → 404,
    API → 404) — the citations in the lane's report could not be re-verified there.
- **Next step:** write the build-aware filter + the SoD id into `classes/hunter.lua`
  (the build decided by the class's own probe at post_init, the same decision that swaps
  the guide's slot set), correct/filter the Mists Raptor cell, then pin the per-BUILD
  HUD slot set, the per-BUILD effective id and the guide/HUD agreement in the three
  test files; mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — The HUD's dead-slot pick is build-aware; the SoD build keeps its Bestial Wrath
- **Worked on:** the hunter's HUD dead-slot pick became **per family AND per build**:
  the ERA family now keeps the Bestial Wrath slot with **no id** until the class's own
  SoD probe (the Chimera Shot rune 409433 — no new client read) decides the build at
  post_init; the **SoD build** ships it with the client's own rank (19574, from the
  shared owner `SPELL_ID_BY_FAMILY.bestial_wrath.SOD`) and the **Era-base build** drops
  it. ONE decision now drives both surfaces: the guide's Era-SoD set gained the slot
  (13 slots) and the HUD's slot takes the same id, so the two cannot disagree. The
  Mists Raptor cell was **removed** (the Mists client's own table carries no Raptor
  Strike among 2973 / 14260..14266 / 27014 / 48995 / 48996 — an id is never guessed):
  the HUD's pick drops the slot there and a new Mists guide slot set (5 slots) does
  not declare it. The Cata Raptor cell was **corrected** 48996 → 2973 (the Cata CLASSIC
  client's own rank). Pins: the per-build HUD slot set and effective id, the
  guide/HUD agreement, the per-family counts (MISTS 9 → 8) and a source pin that the
  table carries no Mists Raptor id.
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the standing floor; the lane's own five files 0/0); **10/10 mutants killed** on
  `/tmp/opencode` copies (M1 = "the SoD build drops a slot it has" → killed by the SoD
  count/key pins); CRLF preserved in `classes/hunter.lua` and `hunter_guide.lua`.
  `tests/hunter_state.lua` PASS (1506) · `tests/hunter_guide_state.lua` PASS (1962) ·
  `tests/hud_state.lua` PASS (817). Report: `bench/hunter_sod_build_2026-10-20.md`.
  **Heads-up for the operator (not a blocker):** the brief's premise that the Era-BASE
  client lacks the Bestial Wrath is **false** — the 1.15.9 client's own data carries
  19574 as a Beast Mastery ability, so the Era-base drop is a ROTATION decision, not a
  client-capability one. The brief pins the Era-base row to keep dropping it (no
  default-visible change beyond the SoD correction) and that is what ships; an
  Era-base BM hunter who learned the talent gets no icon for it — filed as a follow-up
  the operator can rule on. Also filed: the corpus' sim repo (`wago-io/wowsims`) now
  answers **404** for every branch, so every `wowsims/...` citation in the bench is
  currently unverifiable; this lane re-sourced its cells from the clients' own data
  (the operator's local `wow.export` dump + warcraftdb's per-expansion domains).
  `classes/hunter.lua` sits at Lua 5.1's 60-upvalue ceiling — `resolve_guide_icons` has
  **59** (it was 58).
- **Next step:** the orchestrator validates (it owns the release gate) and rules on the
  Era-base Bestial Wrath follow-up; the Mists Raptor id needs an in-client read
  (`GetSpellInfo` by name on 5.5.0) or a Mists spell dump.

## 2026-10-20 — [signal:done] The HUD's dead-slot pick is build-aware; the SoD build keeps its Bestial Wrath
- The hunter's HUD pick is now per family **and** per build: the SoD build of the Era
  client keeps the Bestial Wrath (19574 — the client's own rank, from the shared owner
  table) and an Era-base client still drops it; ONE decision (the class's own SoD rune
  probe) drives the guide's slot set and the HUD's pick, so the two surfaces cannot
  disagree. The Mists Raptor slot is filtered (the client's own Raptor id is unknown —
  never guessed) and the Cata Raptor cell is corrected to 2973. Harness 43/0, luacheck
  2/0 (the floor; the lane's own files 0/0), 10/10 mutants killed. Artifacts:
  `bench/hunter_sod_build_2026-10-20.md` (+ a dated supersession pointer appended to
  `bench/hunter_hud_family_2026-10-20.md`, whose Cata/Mists cells and Era-base premise
  this lane corrects). Validation owner: the orchestrator.


