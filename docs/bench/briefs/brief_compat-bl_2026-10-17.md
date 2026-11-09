# Brief: compat-bl — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/compat-bl/journal.md · desks/journal.md · bench/verify_bank.md (C2 row + §2 id table — BINDING) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
compat.lua + tests/smoke.lua. NOTHING else. (utils.lua read-only.)

## Task
- **C2 shared aura scan**: implement in st.api: `st.api.scan_player_aura(predicate)` → returns `duration_remaining_seconds, stacks` (nil-safe per family; nil = not found/unavailable). Family paths: TBC 0.05s player-aura poll, WotLK aura path, retail `C_` path — all through existing st.api wrappers, no direct cross-client API calls. CONTRACT IS FROZEN: parallel lanes (hunter H2, paladin P3) code against this exact signature.
- **Bloodlust window ids (CONFIRMED, verify_bank §2)**: 2825 (Bloodlust/Horde) + 32182 (Heroism/Alliance) as a first-class "lust window" input. Era gate: Bloodlust/Heroism is TBC+ only (confirmed) — BL helpers must NOT arm on Classic Era (gate through st.family / WOW_PROJECT_ID patterns, not version strings).
- **Exhaustion/Sated 57723/57724: UNCONFIRMED** (verify_bank — no primary source). Register with explicit UNCONFIRMED comment + in-client check item; the code must not hard-depend on them.

## Cross-client rules
Secret-value guards per existing compat patterns. New API nil-safe. Minimal in-place edits, preserve formatting/line endings, no `_` renames, no unused-variable work.

## Validation (run yourself)
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_compat-bl/ (break the Era gate or the nil path, show the check fails, restore). Extend tests/smoke.lua with family/profile coverage for the new wrapper + ids.

## Deliverables
Code · desks/compat-bl/journal.md entry · signal JSON in desks/compat-bl/.signals/ · bench/buildout_compat-bl_2026-10-17.md (changes, evidence, the frozen contract restated, UNCONFIRMED list, option defaults). Final reply ≤6 lines. NEVER run git.
