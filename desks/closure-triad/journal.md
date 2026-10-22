# Closure Triad — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close three filed items the last wave left behind (one lane, one brief):
  1. the `hud_show_coe` options widget + default (the Call of the Elements HUD mirror
     shipped; the widget + default were filed to the options pass by the shaman lane);
  2. the shaman gather's stale Flame Shock fallback (`or 3` vs the shipped default 0);
  3. the druid's hot Wolfshead read (`api.is_item_equipped(8345)` per gather, ~380
     item reads/s for an input nothing consumes yet).
- **Scope (from the dispatch):** `option_tables.lua` (the CoE widget only),
  `config_presets.lua` (the CoE default only), `classes/shaman.lua` (the FS fallback
  line only), `classes/druid.lua` (the wolfshead read path only),
  `tests/options_load_state.lua`, `tests/shaman_state.lua`, `tests/druid_state.lua`.
- **Out of scope:** `practice*.lua`, `compat.lua`, `shaman_guide.lua`, `druid_guide.lua`,
  other classes, `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`, `run.sh`, TOCs,
  versions, README/CHANGELOG/docs; no git commits; no lint-config changes.
- **Filing trail (read before working):**
  - CoE widget: `bench/shaman_coe_ss_2026-10-19.md` §"Filed" (the `hud_show_coe`
    widget + default are the options pass's job), `desks/shaman-coe-ss/journal.md`.
  - FS fallback: `desks/options-pass/journal.md` — "`classes/shaman.lua:3264`'s `or 3`
    gather fallback still says 3 (shaman lane)".
  - Hot read: `desks/druid-wolfshead/journal.md` — "the probe walks all 19 equipped
    slots on every gather (~380 reads/s at the guide's 0.05 s tick)".
- **Rules:** nil-safe; unknown-hides; no default-visible change (the CoE mirror is
  nil = off); wire-not-strip; preserve line endings; touched-lines whitespace only;
  mutation proofs on `/tmp/opencode` copies (a "hot read restored" mutant must fail
  a pin).
- **Next step:** read the three consumers, implement, pin, run the harness + luacheck,
  prove the mutations, file the bench artifact + signals.

## 2026-10-19 — [signal:done] the triad closed (harness 41/0, luacheck 2/0, 5/5 muts)
- **Worked on:** the three filed items, one lane.
  1. **The CoE widget + default.** `option_tables.lua:5925-5932` (the toggle,
     between the Searing mirror and the trinkets, so the row's order mirrors
     `ST.SHAMAN.HUD_SLOTS`) + `config_presets.lua:1090-1097`
     (`hud_show_coe = false`). The **consumer is cited in the code**:
     `classes/shaman.lua:3488` declares the `"coe"` descriptor and
     `classes/shaman.lua:3659-3664` hides the slot unless
     `hud_db["hud_show_" .. slot.key] == true` (nil = off). The glow copy
     (`option_tables.lua:5939-5943`) now names the third mirror — the old "No
     other icon glows" would have contradicted it.
  2. **The Flame Shock gather fallback.** `classes/shaman.lua:3400-3405`:
     `db.guide_flameshock_refresh or 3` → `or 0`. The shipped default is 0
     (the sim re-applies only on expiry), so a profile with a missing option key
     no longer falls back to the old 3 s clip. `0` is truthy in Lua, so an
     explicit 0 rides through the `or` untouched.
  3. **The druid hot read.** `classes/druid.lua:1818-1853` + `:1953-1958`: the
     probe is now **throttled to one read per second**
     (`WOLFSHEAD_REFRESH_SECONDS = 1.0`) instead of one per gather (~380 item
     reads/s → ~19). The **freshness contract is documented** at the constant and
     at the call site: a gear change is visible within 1 s of the gather that
     follows it; the published value is always a real probe answer (true /
     false / nil — unknown is never false); an unknown read stays unknown until
     the next refresh; the field is still written on **every** call, so a reused
     input table never keeps a stale answer. The tri-state is intact and the
     "no rule consumes it" pins stay green (`tests/druid_guide_state.lua`
     95518 checks).
- **Files changed (7 + the workshop surfaces):** `option_tables.lua`,
  `config_presets.lua`, `classes/shaman.lua`, `classes/druid.lua`,
  `tests/options_load_state.lua` (new §26, 23 checks), `tests/shaman_state.lua`
  (new §40, 3 checks), `tests/druid_state.lua` (§38 +4 checks) — plus
  `tests/shaman_guide_state.lua` (see the hands-up below) and the workshop
  surfaces (this journal, `hands-up.md` HU-11, the bench artifact, two signals).
- **Current state:** `bash tests/run.sh` = **41 steps / 0 failed**;
  `luacheck .` = **2 warnings / 0 errors in 83 files** (the standing floor; the
  eight touched files are 0/0 on their own). Line endings preserved
  (`classes/druid.lua` is still CRLF, the rest LF); no trailing whitespace
  introduced. **Mutation proofs 5/5 killed, 0 survivors**
  (`/tmp/opencode/closure_mutations.py`, re-runnable; the control copy is
  green): A "hot read restored" → the 20-gather pin FAILS (got 20, want 0);
  B "throttle window zeroed" → the same pin FAILS; C "FS fallback back to 3" →
  `shaman_state.lua` AND `shaman_guide_state.lua` FAIL; D "CoE widget removed" →
  the options suite FAILS; E "CoE default flipped to true" → the options suite
  FAILS.
- **Artifact:** `bench/buildout_closure_triad_2026-10-19.md` (new bench file; no
  existing bench file was overwritten).
- **Filed / not built:** the engine's own `FLAMESHOCK_REFRESH_DEFAULT = 3`
  (`shaman_guide.lua:447`, pinned at 3) is **out of scope and unreachable from the
  live path** (the gather always publishes a number; the practice surface reads
  the same gather) — a lane owning `shaman_guide.lua` may want to re-cut it. The
  druid **SHIFT rule** stays removed (DU-16: the Furor half is unproven) and the
  "no rule consumes it" pin in `tests/druid_guide_state.lua` is the gate that has
  to be retired deliberately by the lane that lands the rule — that lane must
  also decide whether the 1 s freshness is enough for it. In-client: the 66842
  behaviour on 3.80.2, the Wrath 4pc Glad-4pc 6 s Stormstrike variant, and the
  operator's in-client read of the Wolfshead probe.

## 2026-10-19 — [signal:hands-up] the `tests/shaman_guide_state.lua` scope boundary
- Signal: `desks/closure-triad/.signals/2026-10-20T03-59-00Z.json`; row **HU-11**
  in `hands-up.md`.
- The dispatch listed seven files and excluded `tests/shaman_guide_state.lua`, but
  that file's pin (`:1758-1761`) **asserted the old 3 s fallback** and cited
  `classes/shaman.lua:3264` — the very line the dispatch ordered changed. The
  lane made the **minimum mechanical** re-cut (expected value 3 → 0 and its
  message; no other pin touched) so the harness could be green, and raised the
  boundary for the operator (HU-10 precedent).
- The operator rules: (a) keep the re-cut (recommended — the shipped default 0
  and the gather fallback 0 then agree), or (b) revert the fallback to 3 and keep
  the old pin (which re-opens the filed gap).

