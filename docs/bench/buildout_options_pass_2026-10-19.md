# buildout_options_pass_2026-10-19.md — the BS-7 options pass + the HU-9 badge toggle

Desk: `options-pass`. Date: 2026-10-19.
Spec: `bench/filed_closure_sweep_2026-10-19.md` §7 **BS-7** (three items) **PLUS** the
filed badge toggle **HU-9** (`hands-up.md`, the gamification-visibility vs
practice-progress-ui row).

**Scope held.** `option_tables.lua`, `config_presets.lua`, `tests/options_load_state.lua`,
`tests/shaman_guide_state.lua` (**only** the Flame-Shock-refresh pins). No git, no lint
config, no version/TOC/README/CHANGELOG/docs edits, and no touch of `practice*.lua`,
`classes/*.lua`, `guide_contract.lua`, `hud_state.lua`, `main.lua`, `diag.lua`,
`compat.lua`, `hud.lua`, `bars.lua`, `run.sh`.

**One writer per file.** BS-7 owns `config_presets.lua`; BS-4c (the Flame-Shock flip)
was handed to this lane together with its `tests/shaman_guide_state.lua` pins, so the
shaman lane owns `classes/shaman.lua` / `shaman_guide.lua` / `tests/shaman_state.lua` and
the shaman sections of the two shared suites. This lane touched **no** class file.

---

## 1. What landed — four surfaces

| # | item | where | default | consumer (verified live) |
|---|------|-------|---------|--------------------------|
| 1 | **Forever Rend upkeep toggle** (W-15) | `option_tables.lua:3817-3844` (warrior panel, order 4.132) | **off** — no default entry ships (nil = off), documented at `config_presets.lua:1255-1269` | engine half **live**: `warrior_guide.lua` `should_maintain_rend_outside_arms` (`REND_REFRESH_DEFAULT = 3`) called from rule R (`warrior_guide.lua:1154-1160`). Provider half **FILED**: `classes/warrior.lua:3049-3053` (the warrior lane's file) — see §4.1 |
| 2 | **TBC mana-sustain threshold** (P-22) | widget already existed (`option_tables.lua:2218-2243`, the 0-100 range); **the default** is new: `config_presets.lua:682-697` | **0 = off** (documented) | **live**: `classes/paladin.lua:3281-3285` forwards `db.twist_mana_threshold_pct` → `inputs.twist_mana_threshold`; `nextaction.lua:556-557` throttles the reseal below it |
| 3 | **Shaman Flame Shock refresh default 3 → 0** (BS-4c) | `config_presets.lua:1062-1077` (value + rewritten comment block) | **0** (the sim-exact expiry-only value) | **live**: `classes/shaman.lua:3264` forwards the key; `shaman_guide.lua` rule 6 refreshes only when `flameshock_remaining <= refresh` |
| 4 | **Practice level-badge toggle** (HU-9) | `option_tables.lua:806-846` (Progress page, order 5.1) | **true** — the operator-gated default that already shipped (`config_presets.lua:101-114`) | **live**: `st.practice_ui.badge_is_enabled` / `st.practice_ui.set_badge_enabled` (`practice_ui.lua:1116-1142`) — the module's own entry points, not a copy of its logic |

**HU-9 is answered.** The row's question was "land the toggle widget on the Progress
page …, or ship the badge as unconditional-on?". The widget landed (item 4), so the
badge is now switchable in-game and a user who turns it off **stays off** (the saved
`false` wins over the shipped `true` default — pinned by the existing GAMVIS §24(b)
merge model and by the new §24(e) round-trip pin).

---

## 2. The evidence behind each default

**3 — Flame Shock 3 → 0 (sim-exact).** `bench/filed_closure_sweep_2026-10-19.md` §7
BS-4c and §4.1 S-05: every sim re-applies Flame Shock only when the dot is INACTIVE
(SoD P6/P4, Era default, TBC default, Forever `testing.build` all use `not dotIsActive`;
none refresh early), so the sim-exact value is **0** — expiry only, which the engine
honours as recast-when-missing (`shaman_guide.lua` rule 6). The shipped `3` clipped
~3 s of dot every cycle. The old comment block admitted the value was kept only
because the out-of-scope pin could not move with it; both moved together here.

**2 — the mana-sustain default is 0 (off).** The cited source
(`docs/research/tbc_minmax.md:27`, via `bench/class_features_drills_2026-10-19.md:144`)
says only *"twisting at 100% uptime ooms in 1-2 min without mana support"* — it names
**no percentage**. The TBC sim APLs manage mana through their disabled-by-default
fillers + consumes (`bench/paladin_rotation_audit_2026-10-19.md` TBC GAP), not through
a twist pause. A non-zero default would change the live TBC guide's prompts with **no
operator gate** (the standing rule: no default-visible change without a gate), so the
shipped value is the documented off state and the player sets the percent deliberately.
`0` and `nil` behave identically: `mana_pct` never reads below 0, so
`mana_pct < threshold` is false at 0 (`nextaction.lua:556-557`). The nearest cited
non-zero candidate (the tbc-new shaman's TBC twist mana pause, 10 % — `weave.lua`
`TWIST_MANA_PAUSE_THRESHOLD_TBC`, and the Forever paladin APL's filler gate at
mana ≥ 10 %) is **filed as operator-gated** in §4.2, not shipped.

**1 — the Forever Rend toggle ships off.** The Forever APL's Rend-weave group
(11574, refresh ≤ 3 s) is toggle-gated
(`bench/class_features_drills_2026-10-19.md:292`, `desks/warrior-rotfix/journal.md`:
"Forever 11574 toggle-gated <=3s"), and the pure rule is live in `warrior_guide.lua`.
No default ships: the rule has never run on Forever, and arming a new prompt on that
family is a deliberate choice, not a fresh profile's default.

**4 — the badge default is the operator's, not the lane's.** `config_presets.lua:107-110`
already records the gate: the operator order of 2026-10-19 (*"start at lvl 1, gain xp
each practice, level up"*) **is** the gate for the default-visible change. This lane
changed no default here — it only gave the user the switch the default made necessary.

---

## 3. The pins (all in scope)

`tests/options_load_state.lua`
- §4(a) SIM: `guide_flameshock_refresh` ships **0** (was 3) — the flip's own pin.
- §13(a) MANA: `twist_mana_threshold_pct` ships **0** (was: no default line) — with the
  widget's own 0-100 range, its nil-safe getter and its class setter re-checked.
- §24(e) GAMVIS (new): the Progress page carries the badge toggle; the getter reads
  **false** with no `practice_ui` module and the setter is a no-op (nil-safe); with the
  **real** module injected, the toggle reads on, writes `false` to the class table,
  reads back off, writes `true` back and reads back on.
- §25 (new): the Forever Rend toggle is a toggle widget with an inline get/set; an
  unset key reads **off** (nil = off); the setter writes `true`/`false` to the class
  table; **no default ships**; the key is documented in the WARRIOR defaults block; the
  engine half (`should_maintain_rend_outside_arms`, `REND_REFRESH_DEFAULT`) is in the
  tree; and whenever the provider read lands it must read the key as `== true`.

`tests/shaman_guide_state.lua` (Flame-Shock-refresh pins only)
- the rule-matrix baseline `flameshock_refresh` 3 → **0**;
- the rule-6 boundary pins re-cut to the expiry semantics (*"a live dot is not
  re-applied"*, *"an expired debuff has no countdown left to ride"*) **plus** fresh
  coverage of the engine's own 3 s fallback (`flameshock_refresh = NONE` refreshes at
  exactly 3.0 s) so the engine constant keeps its own proof;
- the fresh-profile fixture `guide_flameshock_refresh` 3 → **0** and the gathered
  default pin 3 → **0**;
- the missing-key pin re-labelled: the **gather's own** 3 s fallback
  (`classes/shaman.lua:3264`) is not the shipped default — the fixture now restores 0;
- the frame block re-cut: an untracked dot → slot lit, no countdown; an expired dot →
  slot lit, no countdown; a live dot → **not** re-applied; and an **explicit override**
  (`guide_flameshock_refresh = 3`) → the live dot inside the window is suggested again
  and the swipe rides the tracker's 12 s debuff length;
- the `config_presets.lua` source pin `guide_flameshock_refresh = "3"` → `"0"`.

---

## 4. Filed follow-ups (outside this lane's scope — named, not guessed)

**4.1 — the Forever Rend provider read (the warrior lane's one line).**
`classes/warrior.lua:3046-3053` currently reads:

```lua
    if inputs.sod == true and self.warrior_has_sod_rend_rune == true then
        inputs.rend_upkeep_enabled = true
    else
        inputs.rend_upkeep_enabled = nil
    end
```

The key this lane ships (`guide_forever_rend_upkeep`) has to reach the engine through
that branch, e.g.

```lua
    elseif is_forever_guide and db.guide_forever_rend_upkeep == true then
        inputs.rend_upkeep_enabled = true
```

`db` is already in scope there (`classes/warrior.lua:2831`). **Until that read lands the
toggle is armed but the rule stays dormant** — the widget is the key + the switch, the
provider carries it. The options suite pins that a landed read must use `== true`
(nil = off), so the contract cannot rot silently.

**4.2 — a non-zero TBC mana-sustain threshold is operator-gated.** The candidate number
and its citations are in §2; shipping it changes the live TBC guide's prompts, so it
needs an operator order (the same shape as the badge's gate). The widget + the default
are in place, so the operator's word is all that is missing.

**4.3 — `classes/shaman.lua:3264`'s fallback still says 3.** The gather reads
`db.guide_flameshock_refresh or 3`. The shipped default is now 0, so in practice AceDB
supplies 0 and the fallback is dead code — but a class table without the key would
still read 3. The line belongs to the shaman lane (this lane may not touch
`classes/*.lua`); the pin in `tests/shaman_guide_state.lua` names it explicitly so the
fix is a one-liner.

**4.4 — the Flame Shock slot's cooldown swipe never rides at the shipped threshold.**
`nextaction_ui.lua:625-640` only swipes a slot while it is the *suggested* action, and
at threshold 0 the guide only suggests Flame Shock when the dot is absent or expired —
so the guide icon shows no countdown. The dot's remaining time is still visible on the
shaman's own Flame Shock bar (`show_shaman_flame_shock_bar`). If the countdown should
keep riding on a live dot, the FS guide slot needs `swipe_always = true`
(`classes/shaman.lua` — the shaman lane's file). **A design call, not a defect.**

**4.5 — two stale comments in class files (read-only for this lane).**
`classes/paladin.lua:3279-3280` still says the mana governor's default is owed to the
options pass (it is not any more), and `classes/warrior.lua:3047-3048` says the Forever
toggle "lives with the options lane (OUT), so Forever feeds nil (dormant) until it
ships" — the key now ships; only the read is missing (§4.1).

**4.6 — HU-9's row.** The widget landed; the operator closes the row
(`hands-up.md` is not this lane's file).

---

## 5. Validation

- `tests/options_load_state.lua` → **3408 checks / 0 failed** (the SIM pin, the MANA
  pin, the new §24(e) badge-widget block and the new §25 Rend block are the only
  additions this lane made to the count).
- `tests/shaman_guide_state.lua` → the Flame-Shock pins are green.
- Full harness `bash tests/run.sh` → **41 steps, 0 failed**. (Mid-run the only two
  reds were the **shaman lane's** CoE pins — `tests/guide_contract.lua` 17 → 18 guide
  slots and 10 → 11 HUD row, `tests/hud_state.lua` the same row — files this lane may
  not touch; that lane landed its shared-suite pins at 23:32 and the tree went green.)
  `luacheck .` → **2 warnings / 0 errors in 83 files** (the tree floor, unchanged: the
  four files this lane touched are **0/0**).
- Line endings preserved: all four touched files are LF (unchanged), no trailing
  whitespace introduced.
- **Mutation proofs** on `/tmp/opencode/bs7_mut` (a full copy of the tree; every
  mutation applied, checked, restored — `cmp` byte-identical afterwards):
  **11/11 killed.**
  M1 the Flame Shock default back to 3 → the SIM pin fires;
  M2 the mana default to 25 → the MANA pin fires;
  M3 the mana default deleted → the MANA pin fires;
  M4 the badge widget removed → the Progress-page pin fires;
  M5 the badge getter hard-coded false → the "reads the real module" pin fires;
  M6 the badge setter neutered → the "writes false to the class table" pin fires;
  M7 the Rend widget removed → the Rend pin fires;
  M8 the Rend getter always true → the "an unset key reads off" pin fires;
  M9 the Rend key given a `true` default → the "no default ships" pin fires;
  M10 `shaman_guide.lua`'s rule-6 boundary `<=` → `<` → the "exactly 0 refreshes" and
  "the engine's own 3 s fallback" pins fire (the copy only);
  M11 the gather's fallback 3 → 99 → the "missing option falls back to the gather's own
  3 s fallback" pin fires (the copy only).
  Script: `/tmp/opencode/bs7_mutations.py` + `/tmp/opencode/bs7_mutations2.py`.

**Validation owner: the orchestrator.** Nothing here has been observed in a game
client — every claim above is offline (CAIRN's two proofs, kept apart).
