# Brief: enemy-swing — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/enemy-swing/journal.md · desks/journal.md · bench/verify_bank.md (§5 row 7: target swing timer) · bench/discover_features.md (SuperSwingTimer enemy swing bar row #1) · AGENTS.md (toc conventions + swing engine notes) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
NEW enemy_swing.lua (exact name) + ALL SEVEN toc variants (SwedgeTimer.toc, _Vanilla/_TBC/_Wrath/_Mainline/_Cata/_Mists) + tests/enemy_swing_state.lua (NEW, exact name) + tests/run.sh. NOTHING else — you are the round's only toc/run.sh writer.

## Task
- **Hostile-target MH swing bar** (SuperSwingTimer model): driven by PLAYER_TARGET_CHANGED, UnitGUID, UnitAttackSpeed, hostile CLEU SWING_DAMAGE/SWING_MISSED (ignore off-hand hits). Frame drawn in your own module (parent to the bar stack per existing layout hooks); no edits to bars.lua.
- **Family gating**: classic-line families only (CLEU SWING_* exists there). Forever/Camelot has NO classic combat log — the bar must degrade to hidden there cleanly. Retail: hidden (like stand-in engines). Gate through st.family/compat patterns, never on st.is_mainline alone or version strings.
- **Default OFF** toggle (nil-safe read, documented for the options pass) — new user-visible feature.

## TOC + harness duties (exact)
- Add the load line for `enemy_swing.lua` (matches the swing_source.lua naming style) in EVERY flavor toc: backslashes, case-exact paths, inserted in dependency order (after swing_source.lua/compat.lua, before class files). Preserve each toc's line endings as found — do not re-encode.
- tests/enemy_swing_state.lua must be load-order-independent (stub the api like smoke does).
- run.sh: add exactly TWO steps — `tests/paladin_state.lua` and `tests/enemy_swing_state.lua` (insert near the other state suites; the warrior/shaman steps already exist). Expected counters 33 → 35.

## Validation
bash tests/run.sh — all green (37 steps after your edits). luacheck 0 errors (new files included). toc_check.lua must still pass (it validates casing/duplicates/coverage automatically). Mutation proof on /tmp/opencode/mut_enemyswing/ (break the family gate, show check fails, restore).

## Deliverables
Code · desks/enemy-swing/journal.md entry · signal JSON · bench/buildout_enemy-swing_2026-10-17.md (toc diffs summary, family gate matrix, option defaults, UNCONFIRMED items). Final reply ≤6 lines. NEVER run git.
