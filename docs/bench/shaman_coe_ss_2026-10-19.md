# bench/shaman_coe_ss_2026-10-19.md — the Call of the Elements line (S-20 / U-10) + the per-family Stormstrike fallback (S-23 / U-09)

Desk: `shaman-coe-ss`. Date: 2026-10-19. Spec: `bench/filed_closure_sweep_2026-10-19.md`
§7 **BS-4** (the shaman class side: 4a + 4b; **4c is NOT this lane** - the Flame Shock
default flip belongs to the sibling options lane). Validation owner: **orchestrator**.

**Scope (as dispatched):** `classes/shaman.lua`, `shaman_guide.lua`,
`tests/shaman_state.lua`, `tests/guide_contract.lua` (shaman sections only),
`tests/hud_state.lua` (shaman section only).
**Scope deviation (hands-up HU-10):** `tests/shaman_guide_state.lua` was excluded
by the dispatch but had to take the **minimum mechanical** slot-count update - see §5.

---

## 1. What shipped

### 1.1 The water-totem clock (the probe S-20 filed)

| Piece | Where | What it does |
|---|---|---|
| `WEAVE_TOTEM_SLOTS` | `classes/shaman.lua` (the client's own slot map, cited) | `FIRE = 1, EARTH = 2, WATER = 3, AIR = 4` - the four former `WEAVE_TOTEM_*_SLOT` locals folded into ONE cited table (the chunk is at Lua 5.1's 200-local limit) |
| `ST.SHAMAN.get_water_totem_clock(self, now)` | `classes/shaman.lua` | `api.GetTotemInfo(slot 3)` → `(remaining, duration)`; `remaining = duration - (now - start)` on the `api.get_time()` axis; **tri-state**: the seconds left, `0` for an affirmatively EMPTY slot (the drop is due), `nil` for an unknown read (no API / MayReturnNothing / throwing / secret field / unreadable start or duration) |
| `inputs.water_remaining` / `inputs.water_duration` | the gather | the pair, published on every call (nil when unknown) |
| rule **9c** | `shaman_guide.lua` | `st.family == "WRATH"` and `water_remaining < COE_WATER_REFRESH_SECONDS (20)` → action `"coe"` |
| guide slot **18** | `classes/shaman.lua` | `{ key = "coe", spell_id = 66842 }` - no swipe (a maintain, like the Lightning Shield / Searing mirrors) |
| HUD mirror | `classes/shaman.lua` | `{ key = "coe", title = "Call of the Elements", … }` - display-only (`HUD_SKIP_GCD`), hidden unless `hud_show_coe` reads exactly **true** (nil = off), glows while the water totem is under 20 s, counts the water totem down |
| rotation line | `classes/shaman.lua` | `live = false` → **`live = true`**, with the citation rewritten |

### 1.2 The per-family Stormstrike fallback (S-23 / U-09)

`ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS = { ERA = 20, TBC = 10, WRATH = 8, SOD = 6, DEFAULT = 10 }`
(published on the class namespace - the chunk is at the 200-local limit).

* `ST.SHAMAN.get_stormstrike_cooldown_seconds(self)` - the ERA token carries both
  builds, so the **SoD MW-rune latch** picks 6 s over the Era-base 20 s; every other
  family reads its own entry; a family with no sourced value (Forever, Retail, an
  unknown token) keeps the shipped 10 s - **no number is invented**.
* The **guide slot's** static `swipe_duration` is refreshed by the gather before the
  frame renders it (the frame reads `slot.swipe_duration` after the gather, on the
  same tick). The gathered client duration still wins when a real cooldown runs.
* The **HUD mirror's** fallback goes through the new
  `ST.SHAMAN.get_hud_cooldown_fallback(self, slot)` accessor (the same per-family
  table), so the mirror can never show another family's length.

### 1.3 No default-visible change

The CoE HUD mirror hides unless `hud_show_coe` reads exactly true (nil = off - the
provider-level hide is the gate; the options pass owns the default + the widget, and
`config_presets.lua` is **not** this lane's file). The guide slot only lights when
the rule fires (WRATH + water under 20 s). The HUD row's geometry is unchanged: a
provider-hidden slot reserves no row width, so the row still sizes to the six shown
slots (`tests/hud_state.lua` pins the width).

---

## 2. The sources (every number, re-fetched this session — nothing remembered)

### 2.1 The client source (READ-ONLY `git -C /home/sam/wow-ui-source show`)

| Fact | Source | Line |
|---|---|---|
| the totem slot map | `classic_titan:Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua` → `FIRE_TOTEM_SLOT = 1; EARTH_TOTEM_SLOT = 2; WATER_TOTEM_SLOT = 3; AIR_TOTEM_SLOT = 4;` | **:286-289** (the same block on `classic_era` 1.15.9 and `classic_anniversary` 2.5.6) |
| the same map, Forever | `origin/forever:Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua` | **:226-229** |
| the id 66842 | `classic_titan:…/Classic/Constants.lua` → `TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 };` | **:300-304** (the same block on `classic_era` / `classic_anniversary`; `origin/forever` at **:240-244**) |

Both were read back out of the mirror during this session (the tree's old
"UNCONFIRMED against FrameXML" note on the water slot was **stale** - it is rewritten
with the citation in the code, in the rotation table and in this file).

### 2.2 The APL rank (fetched live — the rank was NOT owed)

`https://raw.githubusercontent.com/wowsims/wotlk/master/ui/enhancement_shaman/apls/…`
(all three HTTP 200):

| APL | CoE's position | The condition |
|---|---|---|
| `default_wf.apl.json` | **index [9]** - between Earth Shock 49231 **[8]** and Magma Totem 58734 **[10]** | `{"cmp":{"op":"OpLt","lhs":{"totemRemainingTime":{"totemType":"Water"}},"rhs":{"const":{"val":"20s"}}}}` |
| `default_ft.apl.json` | **index [9]** - same neighbours | the same |
| `phase_3.apl.json` | **index [8]** - same neighbours | the same |

So CoE is ranked **between Earth Shock and Magma Totem**, gated on the water totem
being under **20 s**. The engine's rule **9c** sits exactly there in the chain
(after the Searing maintain 9b, before Magma 10) - the sweep's BS-4a instruction
("a rule **above Magma** per the Wrath APL spine") and the bench's spine agree.

**Documented divergence:** the APL ranks Earth Shock *above* CoE, but the frozen
engine keeps Earth Shock at the **bottom** of the chain (rules 14/17 - it is the
shock-capped filler, a frozen TBC-parity order). Honouring "Earth Shock above CoE"
would mean moving Earth Shock, which is out of scope and would change TBC
behaviour; the divergence is written down in `shaman_guide.lua`'s header.

### 2.3 The Stormstrike lengths (fetched live)

| Family | Value | Source |
|---|---|---|
| Era | **20 s** | `wowsims/classic` `sim/shaman/stormstrike.go` → `Duration: time.Second * 20` |
| SoD | **6 s** | `wowsims/sod` `sim/shaman/stormstrike.go` → `Duration: time.Second * 6` (also operator-confirmed in-client 2026-10-19, central journal) |
| TBC | **10 s** | `wowsims/tbc-new` `sim/shaman/stormstrike.go` → `Duration: time.Second * 10` |
| Wrath | **8 s** | `wowsims/wotlk` `sim/shaman/stormstrike.go` → `cooldownTime := TernaryFloat64(HasSetBonus(ItemSetGladiatorsEarthshaker, 4), 6, 8)` - the 8 s base (the 4pc set probe does not exist in this addon, so the base is the fallback) |

The families with no sourced value (Forever, Retail, an unknown token) keep the
shipped 10 s.

---

## 3. The pins

| Suite | Checks | What it pins |
|---|---|---|
| `tests/shaman_state.lua` | **719** (was 670; +49) | the reader's tri-state (unknown / empty / countdown / expired / unreadable length / secret / throwing), the gather pair, the engine rule 9c (the 20 s boundary is exclusive, the family gate, CoE above Magma, unknown-hides), the per-family fallback table (all four families + the SoD latch + the no-sourced-value default), the guide slot's refreshed `swipe_duration`, the HUD accessor, the HUD mirror (toggle gate, unknown-hides, the glow boundary, the countdown, out of combat) |
| `tests/guide_contract.lua` (shaman section) | **1042** | 18 slots / 18 icons, the CoE slot is declared, the HUD declares 11 slots (9 + 2 trinkets) and the CoE mirror, the nil-toggle hide |
| `tests/hud_state.lua` (shaman section) | **675** | 11 HUD slots, the slot order, 11 icons, the CoE mirror hides without its toggle |
| `tests/shaman_guide_state.lua` (out of scope by dispatch) | **1389** | the mechanical slot-count update only — see §5 |

---

## 4. Validation

- **Harness:** `bash tests/run.sh` → **41 steps / 0 failed**.
- **luacheck:** `luacheck .` → **2 warnings / 0 errors** (83 files) - the standing
  floor. Both warnings are pre-existing and in files this lane never touched
  (`compat.lua`, `main.lua`); `classes/shaman.lua`, `shaman_guide.lua` and the four
  touched suites are **0/0**.
- **Mutation proofs** on the `/tmp/opencode/shaman-coe-ss-mut` copy
  (`/tmp/opencode/shaman-coe-ss-mutate.py`, 23 mutations over the four suites):
  **23 killed, 0 survived**. The mutations: the CoE threshold, the family gate, the
  rule body, the rule's rank, the empty-slot branch, the unknown/secret branches,
  the gather feed, the slot number (water → fire), each of the four Stormstrike
  numbers, the SoD latch, the guide-slot refresh, the HUD accessor, the dropped
  guide slot, the HUD toggle gate, the HUD glow, the HUD unknown read, the rotation
  line's live flag, the CoE id, and the water slot number.
- **No git, no lint-config change, no version/TOC/README/CHANGELOG edit.**
- **Line endings preserved** (all six touched files are LF), **no trailing
  whitespace**, the tab indentation of `classes/shaman.lua` preserved.

---

## 5. The scope deviation (hands-up HU-10)

The dispatch excluded `tests/shaman_guide_state.lua` ("a sibling options lane owns
the Flame-Shock default flip + those pins"). The 18th guide slot breaks that file
in five places (the slot count, the icon count, the frame count, the expected
key/icon lists - where the nil icon name **crashes** the file - and the frozen
input mirror). Without a change there the harness cannot be green and the suite
crashes before its own checks finish.

The **minimum mechanical** update was made there:

* the `SPELL_INFOS` fixture entry for 66842 (the icon the frame reads),
* `expected_keys` / `expected_icons` (+`coe` / `icon_coe`),
* `#slots` 17 → 18, `#ui.icons` 17 → 18, `sandbox.frames` 44 → 46,
* the HUD census line (`hud_keys.coe` is now mirrored),
* the frozen-input mirror (+`water_remaining`, `water_duration`),
* the rotation line's `live` flag and the citation check,
* the reason-action list (+`coe`).

**No Flame Shock pin was touched** - the sibling options lane still owns the
default flip and those pins, on different lines, so the two writers do not collide.
The operator should rule on the boundary (keep the update, or revert it and make the
CoE slot WRATH-only, which keeps the file byte-identical but deviates from the
sweep's "the slot count becomes 18" pin).

---

## 6. Filed / still owed

| Item | Status | What it needs |
|---|---|---|
| the `hud_show_coe` widget + default | **FILED to the options pass** | `option_tables.lua` + `config_presets.lua` are **not** this lane's files; the mirror is hidden until the toggle reads exactly true (nil = off), so nothing is visible by default |
| the in-client behaviour of 66842 on 3.80.2 | **STILL OPEN (operator)** | does `GetSpellCooldown` answer for it? does the water-slot read report? does the re-drop cost a GCD? - the same probe the shaman-slots lane filed, now with a live reader behind it |
| the Wrath 4pc Gladiators' Earthshaker 6 s Stormstrike | **FILED** | a set-bonus probe (does not exist); the base 8 s is the shipped fallback |
| the in-client behaviour of the water-slot read | **STILL OPEN (operator)** | the client's own slot 3 read on 3.80.2 - the slot number is client-sourced, the runtime behaviour is not |
| `classes/shaman.lua` at Lua 5.1's 200-local limit | **FILED (structural)** | every new constant must go on the class namespace or the file stops compiling; the next lane will hit this wall |
