# Mutation proofs — 2026-10-27 cross-client / power-bar wave

Method: the shipped tree was copied to a disposable temp tree (no .git/docs/bench/desks/
Media), one text mutation applied, the named suite run from the copy, and the copy removed.
A mutation is KILLED when the suite exits non-zero. All ten were run in one batch against
the final tree; no workspace file was modified by the proofs.

| # | Mutation | Suite | Result | Red pins (first) |
|---|---|---|---|---|
| 1 | Base TOC re-adds 120105 to ## Interface | tests/toc_check.lua | KILLED | "## Interface is exactly 11509, 20506, 38002 (got: 11509, 120105, 20506, 38002)" |
| 2 | hunter_ui Era branch returns the name instead of the id | tests/hunter_state.lua | KILLED | "Era: the probe token is the id..." (Wing Clip vs 2974); "Era: the ranged probe token is the id..." |
| 3 | hunter_ui TBC/Wrath id fallback removed | tests/hunter_state.lua | KILLED | "TBC: a cold name falls back to the id (never nil)" (nil vs 2974) |
| 4 | hunter queue id fallback removed | tests/hunter_state.lua | KILLED | "TBC: a cold name spends one probe per rank id" (0 vs 11); "cold cache sends the rank ids" |
| 5 | hunter_ui.apply_melee_stack made a no-op | tests/hunter_state.lua | KILLED | "the first tick sizes both melee hands" (0 vs 2) |
| 6 | hunter melee stack ignores hunter_melee_stack = false | tests/hunter_state.lua | KILLED | "stack off: no hand is resized" (2 vs 0); "stack off: the mainhand keeps its LibWindow parent" |
| 7 | power_bar.anchor_choice ignores the offhand | tests/power_bar_state.lua | KILLED | "anchor: offhand wins when visible"; "anchor: offhand alone" |
| 8 | power_bar nil power-type guard removed | tests/power_bar_state.lua | KILLED | "a nil power type hides even with numeric power values" (true vs false); 1/151 red |
| 9 | power_bar color_for returns neutral for every type | tests/power_bar_state.lua | KILLED | suite exits non-zero (mana/rage/energy colour pins) |
| 10 | power_bar enabled gate removed | tests/power_bar_state.lua | KILLED | "explicit false hides the bar" (true vs false); "disabled performs zero power reads" (3 vs 0) |

10 / 10 killed. The two behavioural contracts with no direct mutation above are covered by
the same suites: the hunter stack's cast-bar stability pins (a visible/hidden cast bar adds
no restore/move) and the power bar's width/height/anchor pins both run in the same green
suites.
