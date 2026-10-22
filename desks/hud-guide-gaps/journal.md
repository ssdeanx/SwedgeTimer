# hud-guide-gaps — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close per-class HUD, next-action guide, rotation-label, and designmode gaps.
- **Scope:** ONLY classes/*.lua, root *_guide.lua, twist.lua, weave.lua, nextaction.lua, druid_energy.lua, class *_state.lua + *_guide_state.lua tests, tests/bars_state.lua (count pins ONLY for widgets added — nothing else in that file).
- **Out of scope:** option tables/config, guide_contract, smoke, run.sh, TOCs, hud.lua, bars.lua, practice, compat, docs, versions; no git; no invented ids (UNCONFIRMED in caps); no guessing on conflicts.
- **Next step:** verify in-tree per class: HUD slots complete, guide provider live, rotation label wired, designmode integration present; wire missing with pins + mutations; file rest as follow-ups.

## 2026-10-19 — verification complete, no in-scope gaps to wire
- **Worked on:** bench-read (class_matrix, competitor_gaps, lessons, central journal); desk-open (this desk); in-tree verify of all 6 classes x 4 systems (HUD_SLOTS + get_hud_state, guide + gather, get_rotation_key, setup visuals + bars_state + presets) + root pure modules (twist/weave/nextaction/druid_energy + 5 guides) + suite pins; full harness `bash tests/run.sh` 37/0 + luacheck 2/0 re-verified on untouched tree.
- **Current state:** ADEQUATE. All four systems WIRED for all six classes (anchors in bench/perclass_hud_guide_verify_2026-10-19.md §§1-6). D1 hunter order CLOSED as documented behavior (five-class-gaps rationale); D2 rogue empty ids BY DESIGN; D3/D4 rogue bars_state pins PRESENT (no drift). Zero files changed — every remaining gap needs an out-of-scope file (§7 filed follow-ups: rogue icons/contract/UI, warrior/druid/shaman/paladin/hunter slots + options + compat/main + in-client proofs, shaman HUD mirror, options-pass widget debt). No new pins owed, no mutations owed (no behavior changed).
- **Next step:** orchestrator validation; options/compat/slot lanes pick up §7; owner in-client test session (all visuals UNCONFIRMED in-client).

## 2026-10-19 — [signal:done] per-class HUD/guide/rotation/designmode verified, gaps filed
- Bench artifact bench/perclass_hud_guide_verify_2026-10-19.md; zero addon files touched per scope; harness 37/0 + luacheck 2/0 on untouched tree.
