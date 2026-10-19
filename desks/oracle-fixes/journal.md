# oracle-fixes — Journal

## 2026-10-17 — Desk opened
- **Purpose:** close oracle R1–R4 + N2/N3 (R2 secret-hole, R4 nil-semantics, R1 string-payload fallback, R3 P1 Forever gate, bars_state comment refresh, "(future)" copy). N1 rides the changelog lane.
- **Scope:** compat.lua, twist.lua, classes/{paladin,warrior,hunter}.lua, 5 suites, option_tables N3 line, bars_state comments. Nothing else.
- **Next step:** execute bench/briefs/brief_oracle-fixes_2026-10-17.md; numeric paths byte-identical, both payload shapes pinned.

## 2026-10-17 — Buildout complete (verified offline)
- **What was done:** R2 first (compat `scan_player_aura` no-break + `st.cleu_supported` probe; hardened the same hole in paladin `parse_seals`/JotC/guide scans + warrior merged-debuff/Rend/Shield-Block scans), R4 (`== true` both consumers + stale P3 comment fix), R1 (twist `detect_twist_success_name` + paladin/warrior CLEU string branches; numeric branches untouched), R3 (P1 badge `cleu_supported` gate with classic-line-only notice), N2 (bars_state breakdown comments recomputed from setup code: PALADIN 11/5/1/23, WARRIOR 25/10, HUNTER 14/4/6, DRUID 18/6/1 — all sums verified), N3 (`hunter_multi_target` name +"(future)").
- **Out of scope, verified only:** shaman.lua:444/1263 + druid.lua:560/608 still break-on-nil (hole shape present; owner lane needed — recorded in buildout report).
- **Validation:** `bash tests/run.sh` → 35 steps, 0 failed; `luacheck` 0 errors, same 2 KEEP-ruled warnings (compat line shifted 34→36 by the header doc). 5 mutations on /tmp/opencode copies all discriminate (R2 break-restore → hole pin fails; R2b parse_seals break-restore → 3 R2 pins fail; R4 nil-restore → paladin nil pin fails 0.24-vs-0.4; R1 string-strip → 6 string pins fail / numeric pass; R3 gate-strip → 3 Forever pins fail, reproducing the unexplained `0% (0/1)`).
- **Honest limits:** verified offline only; Anniversary string payloads remain UNCONFIRMED (owner `/dump` check still needed); shaman/druid secret-hole loops unhardened (not this lane's scope).
- **Report:** bench/buildout_oracle-fixes_2026-10-17.md. **Next step:** changelog lane (N1), then owner in-client session.

## 2026-10-17 — Secret-hole follow-up complete (verified offline)
- **What was done:** applied the proven R2 pattern to the 4 remaining loops — shaman `scan_weave_auras` (~444) + `scan_target_debuffs` (~1263), druid `scan_target_druid_debuffs` (~560) + `scan_player_druid_buffs` (~608). All 4 confirmed scan loops on re-read (no unmodified-with-reason cases). Early-return-on-found preserved in all 4.
- **Suite churn (truthful, reconcile precedent):** shaman_state exact-cost pins 5→40 and 2→40 (full-cap walk); added secret-hole fixtures to both suites (MW+lust / FS below a secret row; Mangle / Clearcasting below a secret row).
- **Validation:** `bash tests/run.sh` → 35 steps, 0 failed; `luacheck` 0 errors, same 2 KEEP-ruled warnings. Mutation on a /tmp/opencode copy (weave break restored) → its 2 cost pins revert to 5/2 and the 2 weave hole pins FAIL while target-scan pins hold; copy deleted.
- **Out of scope held:** druid_guide_state untouched. Endings preserved (shaman LF, druid CRLF, suites LF). No git, no lint-config.
- **Report:** bench/buildout_secret-hole_2026-10-17.md. R2 is now fully closed across compat + all class loops.
