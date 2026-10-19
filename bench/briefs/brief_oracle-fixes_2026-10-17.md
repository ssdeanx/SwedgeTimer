# Brief: oracle-fixes — close R1–R4 + N2/N3 (standing audit findings)
Date: 2026-10-17. Orchestrator-issued. Source: bench/oracle_audit_2026-10-17.md §§RISK/NITS (READ-ONLY audit; this lane implements).

## Read first (all verified on disk)
desks/oracle-fixes/journal.md · desks/journal.md · bench/oracle_audit_2026-10-17.md (R1–R4 full text + file:lines — BINDING) · bench/lessons.md · CAIRN.md · AGENTS.md (cross-engine rules)

## Scope — writable files (hard boundary)
compat.lua, twist.lua, classes/paladin.lua, classes/warrior.lua, classes/hunter.lua, tests/smoke.lua, tests/twist_state.lua, tests/paladin_state.lua, tests/warrior_state.lua, tests/hunter_state.lua, PLUS option_tables.lua (N3 widget-copy line ONLY) and tests/bars_state.lua (stale comments ONLY, zero pin changes). NOTHING else.

## Task
- **R2 (secret-hole truncation — offline-fixable, do first):** compat.lua `scan_player_aura` breaks at the first nil-name entry; a secret HELPFUL aura above Bloodlust truncates the scan. Remove the early break: iterate the full 1..40 cap, nil = "no match at this index". Worst-case cost identical (40 UnitAura calls already). Add a smoke check with a secret-hole fixture (nil entry above the lust id → still found). Audit the target-debuff consumers for the same hole shape while hardening (oracle names them as likely-clean — verify, harden if not).
- **R4 (nil-semantics — touch-up):** hunter.lua:1067 vs paladin.lua:1007 diverge on `st.lust_supported` nil. Standardize BOTH on `st.lust_supported == true` (closed-on-unknown), per the frozen-contract doc. Pin both branches in their suites.
- **R1 (Anniversary string payloads — harden defensively):** competitor-scan claims Anniversary CLEU sends localized names where classic sends numeric ids (UNCONFIRMED single-source). Implement the fallback WITHOUT changing numeric behavior: paladin `SPELL_DAMAGE` success path (twist.lua:70 via paladin.lua:596-602) + warrior `SPELL_MISSED` OP path (warrior.lua:1240-1244) accept string payloads via localized-name fallback tables resolved through `GetSpellInfo` (established pattern: warrior.lua:1038 target-debuff bars). Suite-pin BOTH payload shapes (numeric + string fixtures); numeric path behavior byte-identical. If twist.lua:70 itself needs the fallback, it is in scope. Log the in-client `/dump` confirmation item in your report — the owner settles UNCONFIRMED.
- **R3 (P1 badge on Forever):** the attempt chain is CLEU-only so the badge sits 0/0 with no explanation where CLEU never registers. Gate per oracle direction: hide the badge or show a "classic-line only" state where twist attempts cannot arm. Pin both states. Do NOT invent a Forever twist engine.
- **N2:** refresh the stale bars_state.lua widget-breakdown comments to the reconciled counts (comments only).
- **N3:** `hunter_multi_target` toggle has no engine yet — append "(future)" to its widget copy so it doesn't read as broken (copy line only; engine is a future round).
- N4/N5/N6: no action (oracle-ruled). N1 (120100-only docs): NOT this lane — changelog lane owns it.

## Rules
Wire-not-strip; never `_`. No git, no lint-config, endings preserved. Never gate on st.is_mainline alone. Numeric/behavioral paths unchanged except where the risk directs; every change mutation-proofed.

## Validation
bash tests/run.sh → 35 steps, 0 failed. luacheck 0 errors, still 2 KEEP-ruled warnings. Mutation proofs on /tmp/opencode copy per change (R2 break-restore, R4 nil-restore, R1 string-path removal → string fixture fails / numeric still passes, R3 gate removal).

## Deliverables
Code · desks/oracle-fixes/journal.md entry · signal JSON · bench/buildout_oracle-fixes_2026-10-17.md (per-risk: fix + evidence + remaining in-client check; N2/N3 done; UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
