# buildout_diag — C4 per-tick budget audit (build-out round 1)

Date: 2026-10-17. Desk: diag. Brief: `bench/briefs/brief_diag_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Changes

Writable scope held exactly: `main.lua` (OnUpdate hook lines only), `diag.lua`, `tests/diag_state.lua`. No other file touched; no git ops.

### diag.lua
- New section "Per-tick budget counters (the hand-bar OnUpdate sites)":
  - `diag.tick_sites` — `hand -> { ticks = <n>, seconds = <t|nil> }` module state. Written ONLY by the counting wrapper named below; `st.diag.report` reads it and stays print-only.
  - `diag.wrap_onupdate(self, hand, original)` — called by main.lua at hook-install time. Gate: `self.db.profile.diag_tick_counters`, strictly `true` enables. Any other value (including nil, the default) returns the ORIGINAL function object untouched, so a default session installs a byte-identical script with flat-zero per-tick cost. When enabled, the wrapper counts every tick, forwards `elapsed` unchanged, and — when the clock is capturable — wraps the handler with `st.api.get_time()` reads (compat's aligned clock; raw `GetTime` never enters diag). No clock → `seconds` stays nil → rendered `?` (unknown is never a faked 0.00s).
- Verbose report gains line 4: `ticks on=yes|no mainhand=… offhand=… ranged=… cpu=…`, then secrets as line 5. Labels stable in every state (`?` where not measurable). `on=yes` iff at least one hand wrapper was installed at init. `cpu` = sum of measured seconds across sites, `%.2fs`, or `?` when nothing was measured. Header/field-list docs updated; `diag.MAX_LINES` stays 6 (verbose = 5 lines; the cap test pins both directions).

### main.lua (init_timers hook lines 636–642, tab-indented, formatting preserved)
```lua
		-- hook the onupdate (st.diag may install a per-tick counter wrapper; default OFF
		-- installs the original untouched - see diag.lua's wrap_onupdate)
		local onupdate = self[hand].onupdate
		if st.diag and st.diag.wrap_onupdate then
			onupdate = st.diag.wrap_onupdate(self, hand, onupdate)
		end
		self:get_bar_frame(hand):SetScript("OnUpdate", onupdate)
```
No other main.lua line changed. The decision is frozen at init on purpose: the OFF path must be the identical function object, so a mid-session toggle would cost a per-tick branch — the toggle applies at next login/reload.

### tests/diag_state.lua
Verbose line count 4→5 (`secrets` now line 5, exact strings pinned for both); cap/fallback expectations updated; new section 11: disabled-gate equivalence (nil/false/string gate → original object; missing original passes through; no site recorded; OFF ticks line exact), enabled counting (elapseds forwarded, per-hand counts, seconds accumulate to <1e-9 tolerance, unwrapped hand has no site, exact ON line with a stepped mock clock, report stays print-only), no-clock degrade (ticks run, seconds unknown, `cpu=?`), junk/hostile `tick_sites` never throws; static pins: the `st.diag and st.diag.wrap_onupdate` gate, the `wrap_onupdate(self, hand, onupdate)` call, `SetScript("OnUpdate", onupdate)`, and `function diag.wrap_onupdate` in diag.lua.

## 2. Option default (standing-rule record for the options pass)

- Key: profile `diag_tick_counters` (SwedgeTimerDB, top-of-profile, like `welcome_message`).
- `nil` = OFF (default; nothing shipped in `config.lua` defaults in this pass — adding it there is the options pass's job). `true` = ON for the session at next login/reload. Widget should default to false; no default-visible change in any client.

## 3. Evidence

- `bash tests/run.sh`: **33 steps, 0 failed** (in-repo at final state, including `tests/main_init_state.lua` and `bars_state.lua` — its `script == state.onupdate` pin passes because `st.diag` is absent in those sandboxes → the nil-guard installs the original; re-run green on the mutation copy before the warrior lane's later landing).
- `diag_state.lua`: **181 checks PASS**.
- `luacheck .`: **0 errors**. Warnings: 45 at this lane's pre-change baseline and 48 at final state — **all 3 extra belong to `classes/warrior.lua`** (the warrior lane landed that file in the shared tree after my baseline; it is out of my writable scope, observed and reported, not fixed). My three touched files contribute ZERO new warnings: main.lua's 8 are all pre-existing (lines 48, 70, 107, 113, 125, 396, 659, 1179 — none in the hook block), diag.lua 0, tests/diag_state.lua 0.
- Mutation proofs on `/tmp/opencode/mut_diag/` (full copy):
  1. diag.lua gate short-circuited (`if read(...) ~= true` → `if false`): **6 FAILs** — OFF-equivalence and the OFF ticks line break. Restored.
  2. main.lua hook gate removed (`if st.diag and st.diag.wrap_onupdate` → `if false and …`): **1 FAIL** — the static hook pin. Restored; copy then ran the full harness 33/33.
- Sample blocks below are real module output from a sandbox sim (env-printer capture), NOT in-client output; the clock is a mock (0.0005 s per read), so the `cpu=` magnitude is illustrative only.

## 4. Sample `/st diag` blocks (captured, mocked-clock sim)

Default OFF session (counting never enabled):
```
SwedgeTimer diag: flags stl_ready=true llm_ready=true lrc_ready=true lrc_unavailable=false deadline=no init=yes
SwedgeTimer diag: modules practice=yes hud=yes rotation=yes design=yes providers=1/5
SwedgeTimer diag: ticks on=no mainhand=? offhand=? ranged=? cpu=?
SwedgeTimer diag: secrets api=no
```
Enabled (`diag_tick_counters = true`), PALADIN (mainhand hand only), 72 ticks:
```
SwedgeTimer diag: ticks on=yes mainhand=72 offhand=? ranged=? cpu=0.04s
```
Login (non-verbose) line: **byte-identical to the pre-change baseline** (single config line; no new default-visible output).

## 5. Scope notes / deferred

- "Per-site" = the OnUpdate sites main.lua owns: the hand bars at the init_timers hook (the three hands a class provides). Sub-handler attribution inside `ST:onupdate_common` (class hook, GCD markers, ldb feed) is not visible from the hook site; measuring it would need bars.lua. Deferred — one line only, out of this brief's boundary.
- The TBC aura poll is a `C_Timer` loop, not an OnUpdate site — untouched, correctly out of the "OnUpdate" audit.
- Counters are cumulative since init; no reset verb this round (reload resets). Acceptable for round 1; a `/st diag reset` could join the options pass.

## 6. UNCONFIRMED items

- **UNCONFIRMED:** in-client behavior — the addon was never loaded in a game client this round (offline harnesses cannot). The owner's test session should confirm: `/st diag` verbose line 4 renders, login line unchanged, counters advance on a FERAL/hunter offhand class.
- **UNCONFIRMED:** real attribution magnitudes (μs/tick) per client family and every tick overhead when enabled; the mock clock cannot speak for them.
- **UNCONFIRMED:** sibling-lane interaction — other lanes this round also touch bar/class per-frame paths; the counted handler INCLUDES their `on_bar_update` time by design, so post-reconcile numbers will move. No file collision (my main.lua edit is the hook block only).
- Options-pass items: the `diag_tick_counters` widget/default and any reset verb, plus documenting the toggle's next-reload semantics in the options table description.

Bench rule honoured: nothing overwritten; this is the diag lane's single report file. Cross-references: `desks/diag/journal.md` (2026-10-17 entry), `desks/diag/.signals/20261017T131909Z.json`, `bench/briefs/brief_diag_2026-10-17.md`, `bench/verify_bank.md` C4 row, `bench/discover_features.md` #23.
