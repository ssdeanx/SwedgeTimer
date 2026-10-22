# Brief: rogue-redzone (2026-10-19)

## Objective
Owner-ordered: Classic Era rogue gets a RED zone at the end of the mainhand swing timer marking the post-MH Sinister Strike window, plus a rogue complete-wiring pass. Writer lane.

## Requirement 1 — red Era SS zone
Corpus (do not re-derive; build on it): SS-after-MH-swing CONFIRMED Era / REFUTED-as-unneeded TBC (bench/rogue_deep_2026-10-19.md §1: ClassicRogueCraft swing-timing guide + corroborations; wago SS-timing WA precedent). "Scourge strike" = Sinister Strike (rogues have no Scourge Strike — DK ability; map to SS, never build a nonexistent spell cue).
First verify in-tree (read-only step): existing rogue_ss_band/text geometry (classes/rogue.lua ~:895-910, :997+) and the generic deadzone rendering. Then implement: Era-gated zone (family check, never st.is_mainline alone) at MH bar end covering the post-swing SS window; RED default color per OWNER ORDER 2026-10-19 (the owner is the explicit gate for this default-visible change — record that in code comment + journal); toggle + color options (nil-safe, off hides); hidden when unknown/off-family/toggle-off. Pins in tests/rogue_state.lua + ROGUE pins in tests/options_load_state.lua; mutations on /tmp/opencode copies.

## Requirement 2 — rogue complete wiring
Both-directions check: every ROGUE default key has a consumer; every class consumer has an option + accurate copy. Fix + pin what you find (after the cue-key removal, re-verify).

## Scope
- classes/rogue.lua, config_presets.lua (ROGUE block only), option_tables.lua (ROGUE section only), tests/rogue_state.lua, tests/options_load_state.lua (ROGUE pins only).
- Explicitly OUT: rogue_guide.lua, diag.lua, compat.lua, practice.lua, guide_contract.lua, TOCs, run.sh, version fields, docs. Another lane owns five-class files; another owns CHANGELOG. Crossing is a defect.

## Rules
No git. No lint-config. Wire-not-strip. Touched-lines whitespace. Endings preserved (file-check first). Full harness green + luacheck floor (2/0) + mutations before done. st.api.get_time() timing; swing-activity gating.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write — perform via file ops)
1. bench-read: desks/journal.md, rogue_readiness §§1-2/4, rogue_deep §1-2, lessons.md.
2. desk-open: desks/rogue-redzone/ (create or resume).
3. desk-journal append + signal-write done JSON (files, red-zone behavior + default gate note, wiring fixes, harness).

## Validation owner
Orchestrator: Era rogue shows the red post-swing zone (option-gated, red default per owner order); zero unwired rogue keys; harness + floor green.
