# bench/shaman_slot_options_2026-10-19.md — the options half of the two shaman maintain mirrors

Desk: `shaman-slot-options`. Date: 2026-10-19. Spec: `bench/shaman_slots_2026-10-19.md` §2
(the filed row "the `hud_show_lightningshield` / `hud_show_searing` defaults + the options
widgets"). Validation owner: **orchestrator**.

**Scope (orchestrator-fixed):** `option_tables.lua` (two widgets), `config_presets.lua`
(two defaults), `tests/options_load_state.lua` (pins). NOTHING else — no
`classes/shaman.lua`, `shaman_guide.lua`, `practice*.lua`, `config.lua`, `main.lua`,
`diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, TOCs, versions,
README/CHANGELOG/docs, no other classes, no git, no lint-config.

---

## 1. What shipped

### 1.1 The two widgets (`option_tables.lua`)

Both are slot toggles in the **shaman** section's shared `hud_rotation_widgets` builder
(the same builder the warrior/hunter/druid sections use, so the widget type, order series,
getter and setter are the house shape — `get = "getter"` / `set = "setter"`, the shared
class handler `ST.class_getsetters`).

| Key | Widget | Order | Line |
|---|---|---|---|
| `hud_show_lightningshield` | toggle, "Lightning Shield" | 8.47 | `option_tables.lua:5851` |
| `hud_show_searing` | toggle, "Searing Totem" | 8.48 | `option_tables.lua:5852` |

They sit **between** the rotation slots and the trinkets, mirroring
`ST.SHAMAN.HUD_SLOTS` (`classes/shaman.lua:3339-3342`, where the two maintain mirrors are
declared before the two trinket slots). The builder assigns
`order = 8.41 + (i - 1) * 0.01`, so the trinket toggles shifted from 8.47/8.48 to
8.49/8.50 — no other class's slot toggles move (the builder is per-class), and no pin
holds the old trinket orders.

### 1.2 The two defaults (`config_presets.lua`)

```lua
hud_show_lightningshield = false,   -- config_presets.lua:1064
hud_show_searing = false,           -- config_presets.lua:1065
```

Both in `ST.SHAMAN.defaults`, between `hud_show_twist = true` and `hud_show_trinket1 = true`
— the same position as the widgets (the HUD_SLOTS order).

**False = hidden = no default-visible change.** The druid Claw mirror's shape
(`hud_show_claw = false`, `config_presets.lua:297`): nil-safe (nil = off) and off on a
fresh profile. The two mirrors stay invisible until the player ticks them.

`ST.SHAMAN.HUD_TEMPLATES` is **untouched**: the curated templates do not list the two
slots, so `hud_template_matches` (which only compares the slots a template names) is
unaffected — picking a template still leaves the two mirrors exactly as they were.

### 1.3 The consumer (cited in the widget comment and in the pins)

The live consumer is `classes/shaman.lua` — **not** `hud.lua`:

* `ST.SHAMAN.HUD_SLOTS` declares the two descriptors
  (`{ key = "lightningshield", ... }`, `{ key = "searing", ... }`);
* `ST.SHAMAN.get_hud_state` gates on
  `hud_db["hud_show_" .. slot.key] ~= true` (`classes/shaman.lua:3499`) → the slot is
  hidden unless the toggle reads **exactly true**.

nil = off (the provider hides on anything that is not `true`), and the HUD's own
`hud.lua` hide rule (`== false`) means a **nil** default would have left the slot
wanted — which is exactly why the defaults ship `false` and why the provider-level
`~= true` gate is the no-default-visible gate.

### 1.4 One copy fix (flagged for the orchestrator)

The shaman's glow description (`option_tables.lua:5859-5862`, the `hud_glow_enabled`
toggle's `desc`) read:

> "Stormstrike glows once it is ready in combat, only while the toggle is on. **No other
> icon glows.**"

That sentence became **false** the moment the `shaman-slots` lane landed the two
maintain mirrors: their upkeep cue *is* the glow (`s.glow = ...` in
`ST.SHAMAN.get_hud_state`). The copy now names the two mirrors and keeps the
exclusivity claim for the rest:

> "Stormstrike glows once it is ready in combat, only while the toggle is on. The
> Lightning Shield and Searing Totem mirrors glow while their upkeep is due (no shield
> aura up / the fire totem slot empty), each only while its own toggle is on. No other
> icon glows."

**This is the one edit beyond "two widgets only"** — it touches the copy of an existing
widget (`hud_glow_enabled`'s `desc`), not another key, and it exists only because the
two new widgets contradict the old sentence. It is pinned (so it cannot silently
regress), and the orchestrator can revert it (the pin goes with it) if the lane boundary
is read strictly. No other class's copy was touched.

### 1.5 The pins (`tests/options_load_state.lua` §23, lines 3482-3616)

New section 23, the "S-M1" family:

* the shaman options tree builds;
* per key: a **toggle** widget, a **numeric order**, a name, a description, a **getter
  that resolves**, a **setter that resolves**;
* the getter reads the class key (`true` → `true`; `nil` → falsy = off);
* the setter **writes** the class key (the shared class setter reaches into main.lua /
  bars.lua, which this sandbox does not load — the eight calls it makes are stubbed, the
  same shape §17 uses for `timers_locked`);
* the two toggles sit **between** the rotation slots and the trinkets (the row's order
  mirrors `ST.SHAMAN.HUD_SLOTS`);
* the glow copy names both mirrors;
* `ST.SHAMAN.defaults` ships both keys **false** and ships **no true** for either;
* the **consumer** is cited: the `lightningshield` + `searing` descriptors **inside the
  `ST.SHAMAN.HUD_SLOTS` table** (the find is scoped to that table — the guide slots carry
  the same slot keys, so an unscoped find would pass on the wrong descriptor), the
  `hud_show_` read, and the `~= true` gate.

The suite: **3318 checks, 0 failed** (the baseline without this section is **3286 checks, 0
failed** — this lane adds **32** checks).

---

## 2. Validation

- **`tests/options_load_state.lua`: 3318 checks, 0 failed.**
- **luacheck:** my three files **0 warnings / 0 errors**. The repo total is
  **2 warnings / 0 errors** — the standing floor (the two KEEP-ruled warnings are
  pre-existing: `compat.lua:36` unused `addon_name`, `main.lua:81` `table.pack`). At one
  point during the window the total read **3** — the third was the parallel guard lane's
  brand-new `guard.lua:33` unused `addon_name`, which that lane has since fixed; the
  count is back to 2.
- **Harness:** `bash tests/run.sh` → **41 steps / 1 failed** at this lane's close. The one
  failure is **not** this lane's: `tests/shaman_guide_state.lua` → "the class module is
  reachable from the addon namespace (got nil)" — the HU-7 cleanup (the parallel lane
  removed the `st.SHAMAN = ST.SHAMAN` namespace mirror from `classes/shaman.lua`, per the
  orchestrator's ENGINE-OWNS-FIX ruling, but that suite still pins the old mirror). That
  suite is another lane's file, and it does not load `option_tables.lua` or
  `config_presets.lua`.
  **The proof of independence** (both runs on `/tmp/opencode/sso-iso`, a copy of the repo):
  with this lane's three changes → **41 steps / 1 failed**; with the same copy and this
  lane's three files reverted (the two widgets, the two defaults and the §23 pins
  removed) → **41 steps / 1 failed**, the *identical* failure and message. This lane adds
  nothing to the red.
  During the window the failing set moved several times under my feet while my three
  files were untouched — first `attempt to index field 'guard' (a nil value)` in five
  suites (the parallel F10 guard lane's `st.guard`, new in `guard.lua`, not yet loaded by
  those sandboxes), then `classes/shaman.lua:4189: main function has more than 200 local
  variables` (the same lane's in-flight edit to a file this lane does not own — a hard
  `luac5.1 -p` error), then the HU-7 mirror removal above, with `wiring_check.lua` going
  FAIL → PASS and `guide_contract.lua` + `rogue_state.lua` going PASS → FAIL in between.
  That churn is the crossfire signature: the failures track the sibling lanes' edits, not
  this one.
- **Isolation proof (the copy, never the repo):** on a `/tmp/opencode` copy that carries
  **my three changes** plus the parallel lane's `guard.lua` present in the test sandboxes,
  the harness was **41 steps / 0 failed** — the deliverable is green with the guard lane's
  landing.
- **Mutation proofs:** **13 mutations, 13 killed, 0 void**, control green
  (3318 checks / 0 failed) — on `/tmp/opencode/shaman-slot-opt-mut` copies
  (`shaman-slot-opt-mutate.sh`), the repo tree verified byte-identical to the
  pre-mutation snapshot afterwards.

| # | Mutation | Killed by |
|---|---|---|
| M1 | the `lightningshield` HUD_SLOTS descriptor removed | "the 'lightningshield' HUD_SLOTS descriptor exists" |
| M2 | the `searing` HUD_SLOTS descriptor removed | "the 'searing' HUD_SLOTS descriptor exists" |
| M3 | the provider gate flipped to `== true` | "the provider gate reads hud_show_<key> == true (nil = off)" |
| M4 | the `hud_show_` consumer read removed | the same gate pin |
| M5 | `hud_show_lightningshield` defaults **true** | "ships false" + "ships no true default" |
| M6 | `hud_show_searing` defaults **true** | the same two pins |
| M7 | the `hud_show_lightningshield` widget removed | "has a toggle widget (got nil)" + the order pin |
| M8 | the `hud_show_searing` widget removed | the same two pins |
| M9 | the shared class getter stops reading the class key | 51 pins (this lane's two included) |
| M10 | the shared class setter stops writing the class key | both "setter writes the class key" pins |
| M11 | the glow copy stops naming the mirrors | "the glow copy names the two maintain mirrors" |
| M12 | both defaults removed from `ST.SHAMAN.defaults` | both "ships false" pins |
| M13 | the two toggles swap places | "the maintain toggles sit between the rotation slots and the trinkets" |

**No default-visible change:** the two mirrors are provider-hidden until their toggle
reads exactly true, and their defaults are `false` — a fresh profile's HUD row is
byte-for-byte the same six visible slots it was before (the row's geometry stays at
`6 * 36 + 5 * 2`, pinned by `tests/hud_state.lua`, which PASSES).

---

## 3. Crossfire reported (not mine to fix)

**One red suite at the close, and it is not this lane's:** `tests/shaman_guide_state.lua`
→ "the class module is reachable from the addon namespace (got nil, want table)". The
parallel lane removed the `st.SHAMAN = ST.SHAMAN` namespace mirror from
`classes/shaman.lua` (per the orchestrator's HU-7 ruling, ENGINE-OWNS-FIX: the engine
resolves the class module from the AceAddon table first), but that suite still pins the
old mirror. `tests/shaman_guide_state.lua` and `classes/shaman.lua` are both other lanes'
files — this lane must not touch them. **Evidence of independence:** the same
`/tmp/opencode/sso-iso` copy of the repo fails identically with and without this lane's
three changes (41 steps / 1 failed, same message).

Two earlier crossfire items in the same window, both already resolved by their owners and
recorded here so the next reader does not re-investigate them:

* **`classes/shaman.lua` exceeded Lua 5.1's 200-local limit** (the F10 guard lane's
  in-flight edit; `luac5.1: classes/shaman.lua:4189: main function has more than 200 local
  variables`). A hard syntax error for `luac5.1 -p` and for every suite that loads the
  file — it would have broken the addon on the classic-line clients. The owning lane has
  since landed the fix (the file compiles again).
* **`st.guard` was nil in five test sandboxes** (the same lane's new `guard.lua` not yet
  loaded by `nextaction_ui.lua` / `practice_ui.lua` / `rotationtext.lua`'s sandboxes).
  That lane has since wired the sandboxes (the suites load `guard.lua` now).

---

## 4. What was NOT done (and why)

- **No `classes/shaman.lua` / `shaman_guide.lua` / `practice*.lua` / `hud.lua` /
  `bars.lua` / `main.lua` / `config.lua` change** — out of scope (sibling lanes own
  them).
- **No `ST.SHAMAN.HUD_TEMPLATES` change** — the curated templates do not list the two
  slots; adding them would change what a template pick writes (a behaviour change the
  options pass was not asked for). Filed below instead.
- **No new widget beyond the two** — no `hud_show_*` key was renamed, added or removed
  anywhere else; no practice/design/class-slot key was touched.
- **No git, no lint-config change, no version bump** — the operator owns those.

### Filed for the orchestrator

| Item | Why it is not in this lane |
|---|---|
| **The two mirrors in `ST.SHAMAN.HUD_TEMPLATES`** (a "Full Enhance" template that shows the maintain mirrors) | A template pick WRITES the slot keys — that is a behaviour change beyond "wire the widget + the default". The mirror defaults stay `false` until the player asks, and a template that lists them would flip them on. The templates also never listed the mirrors, so the current state is consistent. |
| **The `hud_state.lua` "ships false" pin for the two shaman keys** (the druid precedent at `tests/hud_state.lua:1222` pins `hud_show_claw = false` in the HUD suite) | `tests/hud_state.lua` is out of this lane's scope. The equivalent coverage IS in this lane's file (`tests/options_load_state.lua` §23: "ships false" + "ships no true default"), and it is stricter than the HUD suite's single check. If the orchestrator wants the HUD suite to carry it too, that is a one-line addition to a file another lane owns. |
| **The S-29 shield choice** (Lightning Shield vs Water Shield) | Unchanged from `bench/shaman_slots_2026-10-19.md` §2 — the maintain only fires while no shield aura is up, so a Water Shield build is never prompted. |
