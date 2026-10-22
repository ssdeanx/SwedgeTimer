# class-isolation-shared — Journal

## 2026-10-21 — Desk opened
- **Purpose:** the operator's order (2026-10-21, verbatim): "no class features so cross each other. each class must use their own functions." This desk owns the SHARED-layer crossings (C1-C4 practice_ui.lua class routes + drill-key literals, C5 rotationtext.lua defining `ST.PALADIN.get_rotation_key`, C6 designmode.lua calling paladin-only functions, C7 shared routes keyed on `ST.player_class` instead of the ACTIVE class).
- **Scope:** `practice_ui.lua`, `rotationtext.lua`, `designmode.lua`, `practice.lua` (class resolution only), `main.lua` (active-class record/expose only), their suites, `tests/wiring_check.lua` (new machine-enforced guard), plus the class providers the contract needs.
- **Contract:** `bench/briefs/brief_class-isolation-shared_2026-10-21.md`.
- **Next step:** read the existing crossing regions with targeted greps, pick the provider contract, wire `ST.active_class`, then implement + prove.

## 2026-10-21 — resume note (network abort vs. disk reality)
- **Worked on:** the orchestrator resumed this lane saying "no code changed". FALSE: the first attempt's edits were already on disk (verified with targeted greps: main.lua:649/682 active_class, practice_ui provider seam, six class providers, partially-updated suites). Continued from disk instead of redoing.
- **Current state:** implementation complete.
- **Next step:** run the harness, then benches + signal.

## 2026-10-21 — landed: provider contract + C1-C7 + guard
- **Worked on:** ONE provider contract (`ST.<CLASS>.practice_panel`, R2 shape (a)) now carries each class's drill route, panel facts (title/idle/hints/drift/progress) and session seams; the four hardcoded practice_ui routes, their session shells, `PRACTICE_DRILL_KEYS` and the drill hints are gone. `rotationtext.lua` no longer defines the paladin provider (moved into classes/paladin.lua as a marked block the suite extracts); `designmode.lua` lost the paladin descriptors and gained the generic `DM.register_element`. `main.lua:ST:activate_class()` records `self.active_class` (nil on no-loader/throw); practice_ui + rotationtext key on it, never `ST.player_class`. New `tests/wiring_check.lua` §10 enforces "no shared module names a class in executable code" comment-blind, plus the active-class pins.
- **Current state:** `bash tests/run.sh` = **44 steps, 0 failed**; luacheck **2 warnings / 0 errors in 86 files**; practice_ui_state 2529/0, rotationtext_state 244/0, designmode_state 664/0, main_init_state 950/0, practice_state 1533/0, wiring_check 875/0 (3 accepted), toc_check 1082/0, rogue_state 1114/0, druid_state 1580/0, options_load_state 3499/0. 11 mutation proofs on `/tmp/opencode/class-isolation-mut` (copy only) all fail their owning suite/guard. Bench: `bench/class_isolation_2026-10-21.md`.
- **Next step:** orchestrator review; operator in-client check (Auto + explicit non-playing pick per class, Start/Stop Fight per drill, design mode seal/success elements only with PALADIN active). Filed follow-ups: the shared class-named report builders (practice_ui.lua:6602/6722) and main.lua's non-practice player_class branches.

## 2026-10-21 — [signal:done] landed and harness-green
- See `desks/class-isolation-shared/.signals/2026-10-21T19-40-50Z.json`; artifact `bench/class_isolation_2026-10-21.md`.
