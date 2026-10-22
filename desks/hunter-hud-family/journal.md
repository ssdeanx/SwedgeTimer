# Hunter HUD Family — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Close the hunter lane's filed residual (bench/hunter_steady_family_2026-10-20.md
  §6.1): **the other HUD slots are still family-blind.** Only the Steady slot was
  family-corrected (TBC 34120 / Wrath the client's own rank / Forever the slot absent).
  Every other HUD slot still carries ONE family-blind id, so a slot can point at a spell the
  running client does not have.
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua` (the frozen-spec header only if the
  guide's display-slot block needs it), `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
  `tests/hud_state.lua` (**the hunter census only** — verify by diff that no other class's
  census changed). No git, no lint config, no other class, no docs/TOC/version, no
  `practice*.lua`, `option_tables.lua`, `config_presets.lua`, `main.lua`, `diag.lua`,
  `compat.lua`, `hud.lua`, `bars.lua`, `guide_contract.lua`, `run.sh`.
- **Method (the brief's three-part discipline):**
  (a) a per-family id table with every id cited; (b) the client's own rank re-pointing the
  slot at runtime where the client exposes one; (c) a family filter that drops a slot the
  running client cannot have (the Steady slot's `HUD_DEAD_SLOTS` shape).
- **Evidence fetched this session (2026-10-20, all recorded in the bench report):**
  * `wowsims/forever sim/hunter/spell_data_auto_gen.go` (the Forever client's own hunter
    spell table) — Raptor Strike 2973..14266, Aimed Shot 19434..20904, Multi-Shot 2643,
    Rapid Fire 3045, Bestial Wrath 19574, Black Arrow 3674/14296, Serpent Sting ..25295,
    Summon Hawk, Sniper Shot; **no SteadyShot and no KillCommand entry**.
  * `wowsims/tbc-new sim/hunter/spell_data_auto_gen.go` — Steady Shot 34120, Kill Command
    34026, Multi-Shot 2643..27021, Raptor Strike 2973..27014, Aimed Shot 19434..27065,
    Black Arrow 3674/14296.
  * `wowsims/wotlk sim/hunter/*` — Aimed Shot 49050, Multi-Shot 49048, Raptor Strike 48996,
    Steady Shot 49052, Kill Command 34026, Bestial Wrath 19574, Rapid Fire 3045, Black
    Arrow 63672.
  * `wowsims/classic` + `wowsims/sod` — Aimed Shot 19434..20904, Multi-Shot 2643..25294,
    Raptor Strike 2973..14266, Rapid Fire 3045; the SoD Steady Shot rune is 437123.
  * `wowsims/cata sim/hunter/*` — Steady Shot 56641, Raptor Strike 48996, Kill Command
    34026, Multi-Shot 2643, Bestial Wrath 19574, Rapid Fire 3045, Aimed Shot 19434.
  * wowhead's own version pages (WEB-CONFIRMED): /forever/ has 19574, 3045, 2973, 2643 and
    **no** 56641/34120/34026; /mop-classic/ has 19434, 3045, 56641, 2643, 34026, 19574;
    the retail pages are 56641 (Steady), 186270 (Raptor Strike), 2643 (Multi-Shot), 19434
    (Aimed Shot), 257044 (Rapid Fire), 34026 (Kill Command), 19574 (Bestial Wrath).
- **Next step:** write the per-family table into `classes/hunter.lua`, point both the guide
  slots and the HUD slots at it, extend the runtime re-point to every HUD spell slot, grow
  the dead-slot filter, then pin the per-family effective id, the per-family slot COUNT and
  the guide/HUD agreement in the three test files. Mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — Every HUD slot is family-correct; the pick-channel comment is fixed
- **Worked on:** the per-family id table (`SPELL_ID_BY_FAMILY`, `classes/hunter.lua:130`)
  for all seven HUD spell slots + the guide's shared slots, with every cell cited to the
  client's own spell data (the wowsims repos' generated tables) or to wowhead's own
  version page; the runtime re-point extended from two slots to EVERY slot (one loop,
  `:2212`) with the Aimed Shot walking its own family's ladder (`hud_aimed_rank_ids`,
  `:302`); the dead-slot filter grew the Forever Kill Command (`:2986`); the guide's
  frozen display-slot block re-cut (`hunter_guide.lua:16`); the HUD census in
  `tests/hud_state.lua` re-cut to run PER FAMILY (the fixture grew one option,
  `opts.spells`, which REPLACES the shared table — the other classes' censuses are
  untouched); the per-family id / count / dead-slot / guide-agreement pins landed in
  `tests/hunter_state.lua` and `tests/hunter_guide_state.lua`. Also: the operator's
  filing — the stale "the engine's drill press carries no action" claim in
  `classes/hunter.lua` (two places) and in the test's clip-drill comment was corrected
  to the shipped contract (the drill-list PRESS wins; the class's live-cast pick
  survives only a press-LESS press), and the two cases are now pinned in the hunter's
  own suite.
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor; the lane's own five files 0/0); **11/13 mutants killed** on
  `/tmp/opencode` copies (the two survivors are EQUIVALENT mutants — the Kill Command
  and the Bestial Wrath carry the same id on every family that has them, so restoring
  their "family-blind" id changes nothing); CRLF preserved in `classes/hunter.lua` and
  `hunter_guide.lua`. Report: `bench/hunter_hud_family_2026-10-20.md`.
- **Next step:** the orchestrator validates (it owns the release gate) and rules on the
  five filed residuals — the biggest one: the **filed residual's Forever claims were
  partly refuted** (the Forever client HAS the Bestial Wrath 19574, the Rapid Fire
  3045, the Raptor Strike 2973 and the Aimed Shot 19434; it lacks only the Steady Shot
  and the Kill Command), and the **SoD client has the Bestial Wrath** while the ERA
  family pick drops that slot for it too (un-picking needs a runtime SoD probe and
  would ADD a HUD icon on SoD — the operator rules).

## 2026-10-20 — [signal:done] Every HUD slot is family-correct; the pick-channel comment is fixed
- The hunter's HUD spell slots now carry the running family's own rank (one owner for
  the HUD slot and the guide slot), the runtime re-point reaches every slot, the Forever
  Kill Command slot is dropped (seven slots there, not eight), and the guide and the HUD
  agree per family. The operator's filing is closed too: the stale "the drill press
  carries no action" claim is corrected to the shipped contract and the two cases (a press
  grades the press; a press-less drill press judges the live cast) are pinned in the
  hunter's own suite.
- Harness 41/0, luacheck 2/0 (the floor; the lane's own files 0/0), 11/13 mutants killed
  (two equivalent mutants, reported as such). Artifact:
  `bench/hunter_hud_family_2026-10-20.md`. Validation owner: the orchestrator.

