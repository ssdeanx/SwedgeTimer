# The paladin's HUD mirror for the WotLK APL utility band — 2026-10-20

Desk: `paladin-hud-band`. **Input:** `bench/paladin_apl_utility_build_2026-10-20.md`
(the APL utility layer) §2.3 and §4 — the lane filed the WotLK **HUD mirror** for
the two new guide slots as "the HUD slot count is pinned in `tests/hud_state.lua`,
which is out of this lane's scope". This lane is that follow-up.

**Scope (exactly two files):**

* `classes/paladin.lua` — the HUD slot descriptors + the HUD provider's band
  branches (the cooldown reader and the provider gate). Nothing else in the file
  was touched.
* `tests/hud_state.lua` — the **paladin** census (§1 slot set, §2 creation
  counts, §5 option gates, §7/§7b/§7c provider, the paladin reflow pins).
  No other class's census changed (diff proof below).

No git, no lint-config change, no TOC/version/option/config change, no other
class touched.

---

## 1. What landed

### 1.1 The two descriptors (`ST.PALADIN.HUD_SLOTS`, appended after `aura_mastery`)

```lua
{ key = "hor", title = "Hand of Reckoning", kind = "spell", spell = 67485 },
{ key = "how_wrath", title = "Hammer of Wrath (WotLK)", kind = "spell", spell = 48806 },
```

* **Ids:** the APL's own — `bench/paladin_apl_utility_build_2026-10-20.md` §2.1
  rows 13 and 14 (`hor` 67485 = wotlk `default.apl.json` i=1, `how_wrath` 48806 =
  i=2). They are the same pair the guide's two band slots carry
  (`classes/paladin.lua`'s `ST.PALADIN.guide.slots`), so the mirror and the
  guide cannot drift apart.
* **Titles:** `how_wrath` is titled "Hammer of Wrath (WotLK)" on purpose — the
  shipped `how` slot is already titled "Hammer of Wrath" (the Era/Forever execute
  spell, and Holy Wrath on Wrath). Two identical labels in one options panel
  would be unreadable.
* **Order:** appended, so the twelve existing descriptors keep their indices
  (the archive-order rule the file's own header states).

### 1.2 The display gate (the druid-Claw shape) — `classes/paladin.lua`'s provider

The mirror is **display-only**: three gates, in this order, **before any read**:

| # | gate | rule | shape |
|---|---|---|---|
| 1 | option | hides unless `hud_show_<key>` reads exactly **true** (nil = off, false = off) | `classes/druid.lua:2685` (the druid Claw) |
| 2 | family | Wrath only — the band is the WotLK APL's | the class's `is_wrath_family` |
| 3 | spell book | a build without the talent answers "unknown" → hides | the engine's own gate (`classes/paladin.lua`'s gather, `is_spell_known_query`) |

The gate sits **before** the cooldown read, so a hidden slot performs **no
reads** (pinned).

### 1.3 The state the mirror carries

* **`hor` (Hand of Reckoning):** the client's own cooldown, read **by name**
  (rank-agnostic — the descriptor's id is a rank-invariant icon fallback, this
  class's HUD convention, the same shape `consecration` / `exorcism` use). The
  client's own duration drives the swipe; **no hardcoded number** ships.
* **`how_wrath` (the WotLK Hammer of Wrath):** the same cooldown read, plus the
  **execute-phase desaturation**: the sim's own gate asks for the spell only
  below 20 % target health, so above it the mirror greys the slot — the row
  never shows a ready spell the engine will not ask for. An unknown target
  health claims **nothing** (the slot keeps its own state).

Both slots are **meaningful HUD state**, so neither was filed: each carries a
real cooldown (see §2 for the sim's own numbers) and the WotLK Hammer of Wrath
adds the execute gate.

---

## 2. The evidence (fetched 2026-10-20, re-read from the sim sources)

`wowsims/wotlk sim/paladin/hand_of_reckoning.go`:

* `:16` — `ActionID: core.ActionID{SpellID: 67485}, // 62124 is the "taunt" part`
* `:29` — `Duration: time.Second * time.Duration(core.TernaryInt(paladin.HasSetBonus(ItemSetTuralyonsPlate, 2), 6, 8))`
  → **a real cooldown** (6 s with the Turalyon's Plate 2pc, else 8 s in the sim's
  model). The sim's number is the *citation that a cooldown exists*; the HUD
  shows the **client's** own number.

`wowsims/wotlk sim/paladin/hammer_of_wrath.go`:

* `:12` — `ActionID: core.ActionID{SpellID: 48806}`
* `:28` — `Duration: time.Second * 6` → **a real cooldown**.
* `:31-32` — `ExtraCastCondition: … sim.IsExecutePhase20()` → the execute
  gate the mirror mirrors (the same 20 the engine arms on,
  `nextaction.lua`'s `how_wrath` arm).

### 2.1 A citation correction for the bench

`bench/paladin_apl_utility_build_2026-10-20.md` §2.2 cites
`hammer_of_wrath.go:18 ExtraCastCondition: sim.IsExecutePhase20()`. The fetched
file has `ExtraCastCondition` at **:31** and `IsExecutePhase20()` at **:32**
(:18 is the `ManaCost` `BaseCost` line). The bench's other citation for the
same file — `:12` for the id — matches exactly, so the file is the same and the
line number is simply off by 13. **The lane's code cites the verified lines**
(`:28` for the CD, `:31-32` for the execute gate). `nextaction.lua` carries the
same off-by-13 citation and is **out of this lane's scope** — filed for the
orchestrator.

### 2.2 In-client UNCONFIRMED (carried, not closed)

* The **spell-book probe on a talent id** is in-client UNCONFIRMED (the APL
  lane's own caveat, §2.4): if the WotLK client answers "unknown" for a
  *learned* Hand of Reckoning / Hammer of Wrath, the mirror stays hidden. The
  HUD mirror keeps the engine's exact gate semantics rather than inventing a
  second one. **The operator's in-client session decides whether another gate
  is needed.**
* The client's real cooldown lengths (the sim models 6 s / 6-8 s; the client
  may differ) — the HUD reads the client's own number, so the display is
  client-truth either way.

---

## 3. The census re-cut (`tests/hud_state.lua`, paladin sections only)

| pin | before | after |
|---|---|---|
| the paladin's slot count | 12 | **14** |
| the expected key order | 12 keys | + `hor`, `how_wrath` |
| the per-index id pins | 12 | + `hor` = 67485, `how_wrath` = 48806 |
| the mirror-key block | 5 mirrors | + the two band mirrors |
| icons built / frames created | 12 / +51 | **14 / +59** |
| the option-gate key list (§5) | 12 keys | + the two band toggles |
| the Era census (§7b) | 12 | **14** |
| the paladin reflow provider counts | 10 | **12** |
| the TBC band pins (§7) | — | new (the family gate + "no read") |
| the Wrath band pins (§7c) | — | new (a whole sandbox: §7c) |

**No other class's census changed.** The diff against the pre-lane snapshot
(`/tmp/opencode/paladin-apl-mut/tests/hud_state.lua`, the APL lane's own
mutation copy) touches only the paladin regions: the paladin block of
`SPELL_INFOS` (two new entries), §1's paladin census, §2's creation counts, §5's
paladin option-gate list, §7/§7b's paladin provider blocks, the new §7c, and the
paladin row's two reflow pins. The hunter / warrior / druid / shaman / rogue
census blocks are byte-identical.

### 3.1 The two census counts that had to move, and why

* **`#HUD.icons` 12 → 14 and `created_frames` +51 → +59:** the HUD builds one
  icon per valid descriptor (4 frames each) — two more descriptors, two more
  icons.
* **The reflow provider counts 10 → 12:** `hud.lua` treats a **nil**
  `hud_show_<key>` as *wanted* (`icon_should_show` hides only on `== false`), so
  a mirror without a default still gets its provider called on every tick. The
  two band slots are wanted-but-provider-hidden, so the count is 12 and the row
  still shows 7 icons. This is the **druid Claw's exact shape** (the druid's
  Claw ships `hud_show_claw = false` *and* the provider gate; the paladin's band
  ships the provider gate only, because `config_presets.lua` is out of scope —
  see §4).

---

## 4. Filed, not built (and why)

| item | what it waits for |
|---|---|
| **the options widget for `hud_show_hor` / `hud_show_how_wrath`** | `option_tables.lua` is **out of this lane's scope**. Without a widget the two slots cannot be turned on from the panel — the same shape the druid's Claw had before its widget landed (`bench/hud_parity_2026-10-19.md` D-1, "options own the widget, filed follow-up"). The keys read **nil** on a fresh profile, which the provider treats as **off**, so nothing changes until the widget lands. |
| **the `hud_show_hor` / `hud_show_how_wrath` defaults** | `config_presets.lua` is **out of this lane's scope**. The druid's Claw ships an explicit `false` default; the band ships none (nil = off, the provider gate). Same visible result (hidden), one less file touched. |
| **the paladin HUD templates do not cover the two new slots** | `ST.PALADIN.HUD_TEMPLATES` lives in `config_presets.lua` (**out of scope**). The templates still name the twelve old slots, so a template apply leaves the two new keys **untouched → nil → hidden**. `tests/hud_templates_state.lua` §1 compares the template's slot count against its own hard-coded list (still 12), so it stays green — but the templates no longer cover the class's *full* slot set (14). **The templates lane owns that re-cut** (twelve → fourteen per template, and the per-template true/false choice for the two band slots). |
| **`nextaction.lua`'s off-by-13 citation** (`hammer_of_wrath.go:18` → `:31-32`) | out of scope; the orchestrator owns the correction (§2.1). |

---

## 5. Validation

* `bash tests/run.sh` → **41 steps, 0 failed**.
* `luacheck .` → **2 warnings / 0 errors in 83 files** — the tree's floor (both
  warnings are the pre-existing ones in `compat.lua` and `main.lua`, untouched
  by this lane). The two files this lane touched: **0 warnings**.
* `tests/hud_state.lua` → **PASS (714 checks)**.
* **Mutation proofs: 9 / 9 killed** (`python3 /tmp/opencode/paladin_hud_band_mutations.py`,
  disposable copies under `/tmp/opencode/paladin-hud-band-mut`):

| mutant | killed by |
|---|---|
| the **option** gate is dropped (the band shows with the toggle unset) | the nil = off pin |
| the **family** gate is dropped (the band leaks onto every client) | the TBC family pin |
| the **spell-book** gate is dropped (a build without the talent shows the slot) | the unknown-hides pin |
| the cooldown read stops using the **name** | the "reads by name" pin |
| the **execute-phase** desaturation is dropped | the 20 % gate pin |
| `hor`'s descriptor id is swapped (67485 → 20271) | the id pin |
| `how_wrath`'s descriptor id is swapped (48806 → 24275) | the id pin |
| the `how_wrath` descriptor is dropped | the slot-count pin |
| the band slots are hidden **after** the cooldown read | the "no read" pin |

  (Three of the first drafts **survived** and were real pin gaps, not script
  bugs: the option and family pins were masked by the spell-book gate, and the
  execute pin was masked by the on-cooldown grey. The pins now isolate one gate
  each — the book's answer is set first, the spell is READY for the execute
  gate — and the mutants are re-cut.)

* **Line endings:** `classes/paladin.lua` stays pure CRLF (5928 CRLF, 0 bare
  LF); `tests/hud_state.lua` stays pure LF (0 CRLF). No trailing whitespace on
  any touched line.
* **Diff proof:** `diff -u` against the APL lane's own mutation snapshot
  (`/tmp/opencode/paladin-apl-mut/`) shows exactly four hunks in
  `classes/paladin.lua` (the slot descriptors, the cooldown reader, the
  provider gate, the execute desaturation — all inside the HUD section) and the
  paladin-only hunks listed in §3 in `tests/hud_state.lua`.
* **Offline only.** Nothing here was loaded in a game client. Per `CAIRN.md`
  ("two proofs, two words") this is a source-cited build with a
  mutation-proofed offline pass, not a verified-in-client one. **Validation
  owner: the orchestrator.**

---

## 6. The operator-visible change (read this before the release)

**None, by default.** Both new slots are hidden on every client until
`hud_show_hor` / `hud_show_how_wrath` read exactly `true`, and those keys ship
**no default** (nil = off). The keys are also **not in any HUD template**, so
picking a template does not switch them on.

The moment the toggles are set (by the options widget, once it lands), the
**WotLK** client gets two more HUD icons: Hand of Reckoning with its own
cooldown swipe, and the WotLK Hammer of Wrath with its cooldown swipe plus the
execute-phase grey. Every other family hides both (the family gate), so no
other client changes at all.

---

## 7. Sources

* `wowsims/wotlk sim/paladin/hand_of_reckoning.go` — `:16` (the id 67485),
  `:29` (the CD).
* `wowsims/wotlk sim/paladin/hammer_of_wrath.go` — `:12` (the id 48806),
  `:28` (the CD), `:31-32` (`ExtraCastCondition: sim.IsExecutePhase20()`).
* `bench/paladin_apl_utility_build_2026-10-20.md` §2.1 (the two rows), §2.2
  (the arms), §2.3 (the guide slots), §2.4 (the gather's reads), §4 (the filed
  HUD mirror).
* `classes/druid.lua:2685` — the druid-Claw display-mirror shape.
* `hud.lua`'s frozen slot/provider contract (the header comment) and
  `icon_should_show` (a nil toggle is *wanted*, false hides).
