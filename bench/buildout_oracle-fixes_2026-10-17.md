# Buildout: oracle-fixes — close R1–R4 + N2/N3
Date: 2026-10-17. Desk: oracle-fixes. Brief: bench/briefs/brief_oracle-fixes_2026-10-17.md (source: bench/oracle_audit_2026-10-17.md §§RISK/NITS).

## 1. R2 — secret-hole scan truncation (done first, clean offline fix)
- **compat.lua `scan_player_aura`**: removed the early `break` on nil-name; the walk runs the full 1..40 cap with nil = "no match at this index". Worst-case cost identical (40 `UnitAura` calls already). Contract comment updated (restricted rows no longer truncate).
- **Same hole hardened while in there** (brief-directed audit; oracle's "likely-clean" did not hold — all broke past nils):
  - paladin `parse_seals` (`while true`+break → `while i <= 40`, skip nils), `get_guide_jotc_remaining`, `pulse_jotc_scan` (stale "truncates at the first unreadable row" comment corrected);
  - warrior `scan_target_warrior_debuffs`, `get_rend_debuff_window`, `scan_player_shield_block`.
  - Early-return-on-match preserved everywhere, so existing exact read-count pins (paladin_state P2/P3 `+1`) still hold.
- **Out of scope, verify-only:** shaman.lua:444,1263 and druid.lua:560,608 still `break` on nil (hole shape present). Not touched per the hard boundary; needs an owner lane.
- **Evidence:** smoke secret-hole fixture (nil index 1, Bloodlust at 2 → found, remaining 30) + paladin R2 (seals + JotC below a secret row) + warrior R2 (Rend + Shield Block below a secret row) pins.

## 2. R4 — lust-gate nil-semantics (touch-up)
- hunter.lua:1068 `if st.lust_supported and ...` → `== true`; paladin.lua:1010 `~= false` → `== true` (closed-on-unknown, frozen-contract spelling). Stale paladin P3 comment ("nil keeps the scan-only behaviour") corrected.
- Finding: the hunter side was already closed-on-unknown (`nil and X` is falsy) — spelling-only; the paladin side was the real divergence (nil → scan-on). Both pinned: true narrows/sees, nil + false stay base/nil.

## 3. R1 — Anniversary string payloads (defensive fallback, numeric path byte-identical)
- twist.lua: new pure `detect_twist_success_name` + `SOC_PROC_NAME_FALLBACK = "Seal of Command"`; `detect_twist_success` untouched.
- paladin `SPELL_DAMAGE`: id first (unchanged), then string-in-id-slot via client-resolved localized names (lazy + 5 s retry, warrior-debuff discipline), then defensive name-in-slot-2; either shape consumes the same pending attempt.
- warrior `SPELL_MISSED`: id tables first (unchanged); string id slot falls back to "Heroic Strike"/"Cleave" literals + client-resolved rank names. Nil id still never matches, as before.
- Suite pins for BOTH shapes (numeric + string fixtures, including a localized-name case); numeric behavior unchanged in-client on classic.
- **Remaining in-client check (owner settles UNCONFIRMED):** `/dump` the `spellId` slot type on a TBC Anniversary CLEU event. If Anniversary sends numerics after all, the string branches stay dormant (dead-safe).

## 4. R3 — P1 badge on Forever (CLEU gate, no Forever twist engine invented)
- compat: new `st.cleu_supported` probe (`CombatLogGetCurrentEventInfo` existence — classic-line true; Retail/Forever false). Consumers gate on this flag, never on `st.is_mainline` alone.
- paladin badge: numeric score only when `cleu_supported == true` and attempts > 0 (unchanged classic behavior); otherwise a "twist scoring: classic-line only" notice when the badge is enabled in combat. Retail keeps its existing early-return invisibility.
- Pins: Forever shows the notice (even over a stale count), classic with 0 attempts still hides.

## 5. N2/N3 (done, no behavior change)
- N2: bars_state CLASSES comments recomputed from the setup code (PALADIN 11/5/1/23 = band+text+badge+judge+seals+JotC+CD-row; WARRIOR 25/10 incl. bank cue + BS badge; HUNTER 14/4/6 incl. cast zone + BW/Frenzy badges; DRUID 18/6/1 incl. marker/glow/countdowns/pips). Every sum verified against the pins; zero pin changes.
- N3: `hunter_multi_target` widget name → "Multi-target mode (manual) (future)". Copy line only; engine still a future round.
- N4/N5/N6: no action (oracle-ruled). N1: not this lane (changelog owns it).

## 6. Validation evidence
- `bash tests/run.sh` → **35 steps, 0 failed** (in-tree, final state). Suite counts now: smoke 135, twist_state 46, paladin_state 188, warrior_state 629, hunter_state 451.
- `luacheck .` → **2 warnings / 0 errors** — the same 2 KEEP-ruled standing warnings (`compat.lua` unused `addon_name`, now line 36 after the header doc; `main.lua` table.pack). No new warnings.
- Endings preserved and uniform per file (CRLF addon files incl. all edits; LF tests/compat/option_tables). No git, no lint-config. Scope held: compat/twist/3 class files + 5 suites + N3 copy line + bars_state comments only.
- Mutation proofs (`/tmp/opencode` copies, since removed): R2 break-restore → hole pin FAILs (nil vs 30); R2b parse_seals break-restore → 3 R2 pins FAIL; R4 nil-restore → paladin nil pin FAILs (0.24 vs 0.4), hunter passes (spelling-only, as documented); R1 string-strip → 6 string pins FAIL, all numeric pins PASS; R3 gate-strip → 3 Forever pins FAIL (and reproduces the audit's unexplained `0% (0/1)` badge). Restores were copy-deletes; the tree was never mutated.

## 7. Residual / UNCONFIRMED list
- Anniversary CLEU payload shape (string vs numeric) — owner `/dump` in-client (R1 branches are dead-safe either way).
- Shaman/druid secret-hole loops (shaman.lua:444,1263; druid.lua:560,608) — still truncate; needs an owner lane (out of this scope).
- All behavior verified offline only; in-client session still owned by the owner checklist (oracle_audit §checklist).

## 8. Files changed (complete list)
compat.lua, twist.lua, classes/paladin.lua, classes/warrior.lua, classes/hunter.lua, option_tables.lua (1 line), tests/smoke.lua, tests/twist_state.lua, tests/paladin_state.lua, tests/warrior_state.lua, tests/hunter_state.lua, tests/bars_state.lua (comments only).
