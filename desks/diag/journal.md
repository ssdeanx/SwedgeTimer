# diag — Journal

## 2026-10-17 — Desk opened
- **Purpose:** C4 tick-budget counters surfaced through `/st diag`.
- **Scope:** main.lua, diag.lua only.
- **Next step:** wait for dispatch brief in bench/briefs/; counters nil-safe, no default-on spam.

## 2026-10-17 — C4 build-out round 1 done (offline-verified)
- **Worked on:** per-tick budget counters. diag.lua gained `diag.wrap_onupdate(self, hand, original)` + `diag.tick_sites` (per-hand `{ticks, seconds}`) and a verbose `ticks on=… mainhand=… offhand=… ranged=… cpu=…` line (line 4 of `/st diag`, before secrets). main.lua changed ONLY the init_timers OnUpdate hook lines (635–642): nil-gated wrap of `self[hand].onupdate` before `SetScript`. Gate = `self.db.profile.diag_tick_counters`, strictly true enables; nil (default) = OFF → the original function object is installed untouched (byte-identical hook, flat-zero per-tick cost). Toggle applies at next login/reload; attribution clock is compat's `st.api.get_time`, seconds=nil → `cpu=?` when unmeasurable (unknown never renders as zero). tests/diag_state.lua: verbose lines 4→5, secrets now line 5, new section 11 (disabled/enabled/no-clock/junk-state), static pins for the hook; vendored Mainline/cata flavors all inherit via the single hook line.
- **Current state:** offline-verified. bash tests/run.sh 33/33 green in-repo; diag_state.lua 181 checks; luacheck 0 errors / 45 warnings (baseline count unchanged, zero new). Mutation proofs on /tmp/opencode/mut_diag: (1) diag gate short-circuit → 6 FAILs; (2) main.lua hook gate removed → wiring FAIL; restored → full harness 33/33 in the copy. Sample `/st diag` blocks captured from a sandbox sim (mock clock) in bench/buildout_diag_2026-10-17.md; login (non-verbose) line byte-identical to baseline.
- **Next step:** in-client `/st diag` read on the owner's test session (offline cannot load the addon); options pass wires the `diag_tick_counters` widget/default; sub-handler attribution (inside onupdate_common) would need bars.lua — out of this brief's scope, noted on the bench.
