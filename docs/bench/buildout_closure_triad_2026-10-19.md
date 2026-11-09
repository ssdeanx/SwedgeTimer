# Closure triad — CoE widget + default, Flame Shock gather fallback, druid hot read

Desk: `desks/closure-triad/`. Date: 2026-10-19. Tree state at the close:
`bash tests/run.sh` = **41 steps / 0 failed**, `luacheck .` = **2 warnings / 0 errors
in 83 files** (the standing floor), mutation proofs **5 / 5 killed** on a
`/tmp/opencode` copy (`/tmp/opencode/closure_mutations.py`, re-runnable).

Three items the last wave filed, closed in one lane. Everything below is offline
evidence; nothing here is an in-client observation.

---

## 1) The `hud_show_coe` options widget + default (filed by the shaman lane)

**The filing.** `bench/shaman_coe_ss_2026-10-19.md` (§"Filed") and
`desks/shaman-coe-ss/journal.md`: the Call of the Elements guide slot + HUD mirror
shipped, but the **widget and the default were filed to the options pass** — the
mirror hides unless its toggle reads exactly true, so without a widget the player
had no in-game way to turn it on.

**The live consumer (cited in the code, pinned in the test).**

* `classes/shaman.lua:3488` — `ST.SHAMAN.HUD_SLOTS` declares the descriptor
  `{ key = "coe", title = "Call of the Elements", kind = "spell", spell = WEAVE_COE_SPELL_ID }`.
* `classes/shaman.lua:3659-3664` — `ST.SHAMAN.get_hud_state` reads
  `hud_db["hud_show_" .. slot.key] ~= true` and hides the slot otherwise. The HUD
  itself hides only on `== false`, so the **provider-level hide is the
  no-default-visible gate** (nil = off).

**What shipped.**

* `option_tables.lua:5925-5932` — the toggle in the shaman section's shared
  `hud_rotation_widgets` builder, between the Searing Totem mirror and the
  trinkets (the row's order mirrors `ST.SHAMAN.HUD_SLOTS`): key `hud_show_coe`,
  name "Call of the Elements", desc "Show the Call of the Elements icon (glows in
  combat while the water totem has under 20 s left)."
* `option_tables.lua:5939-5943` — the glow copy now names the third mirror
  ("Lightning Shield, Searing Totem and Call of the Elements mirrors glow while
  their upkeep is due …"). The old copy said "No other icon glows", which the CoE
  mirror (it glows under the 20 s APL threshold) would have contradicted.
* `config_presets.lua:1090-1097` — `hud_show_coe = false` in `ST.SHAMAN.defaults`,
  the druid Claw mirror's shape: **hidden by default, no default-visible change**
  (nil = off hides it too).

**The pins** — `tests/options_load_state.lua` §26 (new, 23 checks): the widget is
a toggle with a numeric order / name / description, its get/set resolve and
round-trip the class key (nil reads off), the order sits between the Searing
mirror and the trinkets, the glow copy names the mirror, the default ships
`false` and no `true`, and the consumer is cited (the `"coe"` descriptor in
`ST.SHAMAN.HUD_SLOTS`, the `hud_show_<key> == true` gate, the provider naming the
`"coe"` slot).

---

## 2) The shaman gather's stale Flame Shock fallback (filed by the options pass)

**The filing.** `desks/options-pass/journal.md`: "`classes/shaman.lua:3264`'s
`or 3` gather fallback still says 3 (shaman lane)". The shipped default had
already moved to **0** (the sim-exact expiry-only value — every sim re-applies
Flame Shock only when the dot is INACTIVE), so a profile whose option key was
missing fell back to the old 3 s clip: ~3 s shaved off every Flame Shock dot.

**What shipped.** `classes/shaman.lua:3400-3405`:

```lua
inputs.flameshock_refresh = db.guide_flameshock_refresh or 0
```

(`0` is truthy in Lua, so an explicit 0 rides through the `or` untouched; only a
missing key takes the fallback, and the fallback is now the shipped default.)

**The pins.**

* `tests/shaman_state.lua` §40 (new, 3 checks): a missing option falls back to
  **0** (not the old 3 s clip), an explicit 0 rides through the gather, and the
  option still rides it.
* The shipped default itself is pinned by the options suite's SIM block
  (`tests/options_load_state.lua:1412`, `guide_flameshock_refresh` ships 0) — the
  "both" of the filing.
* `tests/shaman_guide_state.lua:1758-1761` — the **stale** pin that asserted the
  old 3 s fallback was re-cut (see the scope note below).

**Residual (out of scope, filed).** The pure engine's own fallback constant
`st.shaman_guide.FLAMESHOCK_REFRESH_DEFAULT = 3` (`shaman_guide.lua:447`, pinned
at 3 by `tests/shaman_guide_state.lua:100`) is unchanged — `shaman_guide.lua` is
not this lane's file. The live path never reaches it: the gather always publishes
a number, and the practice surface reads the same gather
(`practice_ui.lua:4338` → `module.gather_guide_inputs`). A lane that owns
`shaman_guide.lua` may want to re-cut that constant and its pin.

---

## 3) The druid's hot Wolfshead read (filed by the druid lane)

**The filing.** `desks/druid-wolfshead/journal.md`: "the probe walks all 19
equipped slots on every gather (~380 reads/s at the guide's 0.05 s tick) —
harmless while nothing consumes it, but a consuming rule will probably want a
throttled read. That freshness change is a design decision for whoever wires the
rule, so it was not taken here."

`api.is_item_equipped(8345)` walks `INVSLOT_FIRST_EQUIPPED ..
INVSLOT_LAST_EQUIPPED` (1..19 on every supported family, `compat.lua:1121-1150`),
so the per-gather read was ~380 item reads/s for an input **no rule reads yet**
(it is a reserved plug-in point until the Furor half of the powershift basis is
proven).

**What shipped** — `classes/druid.lua:1818-1853` + `:1953-1958`:

* `local WOLFSHEAD_REFRESH_SECONDS = 1.0` — the read runs at most once per second
  (~19 slot reads/s instead of ~380).
* `local function read_wolfshead_equipped(now)` — the cached answer while it is
  still fresh, a fresh probe otherwise. A clock that cannot be read, or that runs
  backwards, re-reads every call (freshness wins over the saving).
* The gather publishes `inputs.wolfshead_equipped = read_wolfshead_equipped(now)`
  — **the field is still written on every call**, so a reused input table never
  keeps a stale answer (the "no stale value survives" contract is unchanged).

**The freshness contract (documented at the constant and at the call site).**

1. A gear change becomes visible within `WOLFSHEAD_REFRESH_SECONDS` (1 s) of the
   gather that follows it.
2. The published value is always a real probe answer — `true` = worn, `false` =
   the read worked and no equipped slot holds it, `nil` = unknown (never false).
3. An unknown read stays unknown until the next refresh; it is never turned into
   a guess about the player's gear.
4. The **tri-state is intact** (`true` / `false` / `nil`) and the "no rule
   consumes it" pins stay green (`tests/druid_guide_state.lua` 95518 checks, the
   behavioural + static pair — the engine still never reads the input).

**The pins** — `tests/druid_state.lua` §38 (4 new checks):

* twenty gathers inside the throttle window never re-read the gear (0 extra probe
  calls) — **this is the "hot read restored" mutant's pin**;
* the cached answer is published between refreshes (it is never dropped to nil);
* after the window closes the probe runs again (2 calls) **and a gear change
  becomes visible** (`true` where the earlier read said `false`).

---

## Mutation proofs (`/tmp/opencode/closure_mutations.py`, re-runnable)

Control: the unmutated copy is green on all four touched suites.

| # | mutant | suite | verdict |
|---|--------|-------|---------|
| A | druid: the throttled read replaced by a direct per-gather `api.is_item_equipped(8345)` (the hot read restored) | `druid_state.lua` | **KILLED** (the 20-gather pin: got 20, want 0) |
| B | druid: `WOLFSHEAD_REFRESH_SECONDS = 0` (the cache never covers a second gather) | `druid_state.lua` | **KILLED** (same pin) |
| C | shaman: the gather's FS fallback back to `or 3` | `shaman_state.lua`, `shaman_guide_state.lua` | **KILLED** (both) |
| D | options: the `hud_show_coe` widget removed | `options_load_state.lua` | **KILLED** |
| E | config: the `hud_show_coe` default flipped to `true` | `options_load_state.lua` | **KILLED** |

**0 survivors.** Every mutant ran on a throwaway copy under `/tmp/opencode`
(`/tmp/opencode/closure-mut` → `/tmp/opencode/closure-mut-run`); the in-tree
files were never touched.

---

## Scope note (one file outside the dispatch's list)

The dispatch listed seven files and excluded `tests/shaman_guide_state.lua`. The
**FS fallback change makes that file's pin false**: `tests/shaman_guide_state.lua:1758-1761`
asserted the gather's own **3 s** fallback and even cited the line
(`classes/shaman.lua:3264`) that this lane was told to change. Leaving it would
have made the harness red, so the lane made the **minimum mechanical** re-cut
(the expected value 3 → 0 and its message; no other pin touched) and raised the
boundary as **HU-11** in `hands-up.md`, following the HU-10 precedent
(`desks/shaman-coe-ss`). The operator rules: (a) keep the re-cut (recommended),
or (b) revert the fallback to 3 and keep the old pin (which leaves the shipped
default 0 and the gather fallback 3 disagreeing — the exact filing).

## Filed remainders (not built here)

* The engine's own `FLAMESHOCK_REFRESH_DEFAULT = 3` (`shaman_guide.lua:447`) —
  out of scope, unreachable from the live path (see §2).
* The druid **SHIFT rule** stays removed: the Furor half of the powershift basis
  is still unproven (DU-16), and the "no rule consumes it" pin in
  `tests/druid_guide_state.lua` is the gate that has to be retired deliberately
  by the lane that lands the rule.
* The in-client passes still owe: the 66842 behaviour on 3.80.2 (does
  `GetSpellCooldown` answer? does the water-slot read report?), the Wrath 4pc
  Glad-4pc 6 s Stormstrike variant, and the operator's in-client read of the
  Wolfshead probe.
