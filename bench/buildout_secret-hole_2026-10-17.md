# Buildout: secret-hole closure — shaman/druid nil-break hardening (R2 remainder)
Date: 2026-10-17. Desk: oracle-fixes (follow-up). Brief: bench/briefs/brief_secret-hole_2026-10-17.md (source: bench/buildout_oracle-fixes_2026-10-17.md §1 + §7).

## 1. Sites (all 4 confirmed scan loops on re-read — none left unmodified)
- shaman.lua `scan_weave_auras` (~444): player HELPFUL 1..40 walk, one-line `break` → `if name ~= nil` wrap, all-found early exit (499-502) preserved.
- shaman.lua `scan_target_debuffs` (~1263): target HARMFUL 1..40 walk, same transform, found early exit (1275-1277) preserved.
- druid.lua `scan_target_druid_debuffs` (~560): 1..40 + pending>0 walk, three-line break → wrap, pending early exit preserved.
- druid.lua `scan_player_druid_buffs` (~608): same shape, same transform.
- Pattern matches the proven R2 fix byte-for-shape: no early break, nil = "no match at this index", early-return-on-found kept so existing exact read-count pins elsewhere still hold. Bodies re-indented one level (tabs shaman, 4-space druid); inline `R2` note at each loop.

## 2. Suite churn (truthful, reconcile precedent)
- shaman_state: exact-cost pins updated to the new walk cost — `5` → `40` (§7 single walk), `2` → `40` (§21 farseer). No behavior pins touched.
- New secret-hole fixtures: shaman (MW stacks + Bloodlust haste below a secret row; Flame Shock bar + label below a secret row) and druid (Mangle bar + fill below a secret row; Clearcasting omen glow below a secret row). Fresh-clock note: the shaman FS pin uses clock 1000 (later sections run at 911; 900 hit the 0.05 s throttle — caught and fixed, documented in-suite).
- druid_state needed no count updates (inequality/throttle pins only).

## 3. Validation evidence
- `bash tests/run.sh` → **35 steps, 0 failed** (in-tree, final). Suite counts: shaman_state 382, druid_state 419.
- `luacheck .` → **2 warnings / 0 errors** — the same 2 KEEP-ruled standing warnings. No new warnings.
- Endings preserved and uniform (shaman.lua LF, druid.lua CRLF, both suites LF). No git, no lint-config. Scope held: 2 class files (4 loop sites only) + 2 suites; druid_guide_state untouched.
- Mutation proof (/tmp/opencode copy, since deleted): restoring the break in the weave walk only → cost pins revert to 5/2 and the 2 weave hole pins FAIL (0 stacks, 1.0 haste), while the target-scan hole pins PASS — the pins discriminate per-loop.

## 4. Residual
- R2 is now closed across compat + all class aura loops. Remaining UNCONFIRMED items unchanged from the parent lane (Anniversary payload shape — owner `/dump`; in-client session still owned by the owner checklist).

## 5. Files changed (complete list)
classes/shaman.lua (2 loops), classes/druid.lua (2 loops), tests/shaman_state.lua, tests/druid_state.lua.
