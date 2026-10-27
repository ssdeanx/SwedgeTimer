# appearance + options defaults — 2026-10-25

Lane: `appearance-options` (desk `desks/appearance-options/`). Dispatch was prompt-only:
no brief file existed on disk under `bench/briefs/` at open time (verified), so the request
text is the brief.

Two operator orders landed on the defaults/options side:

1. **Opaque bar backdrop** ("make the background alpha high so it's not fully see
   through") — the BACKDROP only, not the coloured fill.
2. **Ranged distance bar as a standalone horizontal bar**, ON by default for HUNTER,
   opt-in for every other class — defaults + option copy only; `weave_range.lua` belongs
   to the `bars-range-hunter` lane.

---

## 1. What changed (all five files, nothing else)

| File | Change |
|---|---|
| `config_presets.lua:173` | `ST.bar_defaults.background_color` `{0.0,0.0,0.0,0.85}` → `{0.0,0.0,0.0,1.0}` (RGB unchanged, black). Comment records the storage convention and the migration. |
| `config_presets.lua:104` | shared `ST.class_defaults.weave_range_enabled` stays `false` (opt-in for every class) with the per-class override documented. |
| `config_presets.lua:536` | **NEW** `weave_range_enabled = true` in `ST.HUNTER.defaults` — the explicit operator gate for the default-visible change. |
| `config_presets.lua:1599` | **NEW** `ST.weave_range_default_enabled(class_token)` — single source of truth the options getter shares with the shipped defaults. |
| `config.lua:79-181` | **NEW** one-time migration: `ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG = "appearance_defaults_213"` (:117), `ST.APPEARANCE_OLD_BACKGROUND_COLOR` (:121), `colors_equal` (:133), `preset_owns_background_color` (:142), `ST.migrate_appearance_defaults(profile)` (:157-181). |
| `option_tables.lua:195-224` | ranged-bar toggle: key kept (`weave_range_enabled`), name → "Ranged distance bar", new copy, getter now `nil = class default` (hunter ON, others off), explicit `false` stays off. |
| `option_tables.lua:7377-7390` | `ST:set_opts()` runs the migration first, before any widget can read a colour; both calls `pcall`'d (a bad profile can never abort the options build or login). |
| `tests/appearance_defaults_state.lua` | **NEW** suite, 145 checks. |
| `tests/options_load_state.lua:4389-4489` | **NEW** §29: the set_opts call site driven for real + the widget contract per class (3561 → 3596 checks). |

Not touched, as ordered: `bar_color_default` (`config_presets.lua:160`, still
`{93,58,207,0.85}`), `border_color` (:176), the HUD background (no HUD code reads
`background_color` — repo-wide grep), `bars.lua`, `weave_range.lua`, `classes/**`,
`main.lua`, the TOCs, `tests/run.sh`, CHANGELOG/README/docs, `Libs/**`.

## 2. Why the migration is safe — the storage shape, verified

The brief said: verify the shape, or stop. Verified, not assumed:

- **AceDB copies defaults into a FRESH table per default table.**
  `Libs/AceDB-3.0/AceDB-3.0.lua:88-131` (`copyDefaults`) does
  `if not rawget(dest,k) then rawset(dest,k,{}) end` then recurses, so
  `db.profile[CLASS][hand].background_color` is a plain 4-element array
  `{0, 0, 0, 0.85}` and **never an alias** of `ST.bar_defaults` (`:117-124`).
- **Defaults are applied to EXISTING profiles too, but only where the key is absent.**
  `initSection` (`:181-207`) calls `copyDefaults(tbl, defaults)` on the first access of
  `db.profile` whether or not the profile was already saved; `copyDefaults` writes only
  missing leaves (`:126-128`). Hence: a saved `background_color` survives (why the
  migration is needed) while a saved hunter row **without** `weave_range_enabled` picks
  the new `true` up at login (why the hunter default reaches old profiles).
- **Black is convention-free.** This key ships 0-1 floats while the colour setter
  (`option_tables.lua:1364-1368`) stores `×255` RGB + 0-1 alpha, and `0 == 0.0`. So the
  exact-match test on `{0,0,0,0.85}` is safe, and it is also the whole limit of what can
  be distinguished.
- **The one preset collision is handled.** `Classic Retro` ships exactly
  `{0,0,0,0.85}` (`config_presets.lua` THEME_PRESETS.classic), and applying a preset sets
  `db.theme_preset = <key>` immediately before copying its colours
  (`option_tables.lua:1326-1329`). The migration skips a hand whose **active** preset owns
  the stored colour, so a Classic Retro user keeps 0.85.

**Migration contract:** raises only an exact `{0,0,0,0.85}`; idempotent (flag); nil-safe
(nil/non-table profile, corrupt class row, non-table hand or colour → skipped, never
thrown); once per profile; class rows iterated by the same ten tokens `ST.defaults.profile`
lists.

**Reaches the bar:** `main.lua:416` (AceDB) → `:424` (`set_opts` → migration) → `:795/:860`
(`init_libs` → `init_visuals_template`) → `bars.lua:183/:323`
(`configure_bar_outline`) → `bars.lua:521-524` (`SetBackdropColor(convert_color(...))`).
VERIFIED BY READ; the pixel proof is owed in-client (§6).

## 3. Evidence

`lua5.1 tests/appearance_defaults_state.lua` → **145 checks, 0 failed**
`lua5.1 tests/options_load_state.lua` → **3596 checks, 0 failed** (was 3561; +35)
`luacheck` on the 5 touched files → **0 warnings / 0 errors**
Cross-checks (not this lane's suites, run because the seam is shared):
`tests/hud_templates_state.lua` 965/0 (it calls the real `set_opts`), `tests/bars_state.lua`
957/0 (it expands `ST.defaults` through the real AceDB). `tests/wiring_check.lua` 871/0.

Pinned in the new suite: fresh default opaque; fill/border/GCD/preset colours untouched;
AceDB-shaped fresh profile needs no migration and never aliases the defaults; exact old
default raised across classes/hands; ten custom colours preserved (incl. 0.84 / 0.86
near-misses and non-black RGB at 0.85); Classic Retro preserved; unknown preset name does
not block; second run = 0; post-flag re-seed left alone; nil/non-table/corrupt inputs;
hunter nil→ON, explicit false→OFF, other classes nil→OFF; the appearance migration never
touches the toggle.

Pinned in `tests/options_load_state.lua` §29: the real `set_opts()` marks the profile,
raises a seeded `{0,0,0,0.85}`, preserves a seeded custom colour, and a third run is a
no-op; hunter `nil → ON` / `true → ON` / `false → OFF`; rogue/warrior/paladin/shaman/druid
`nil → OFF`; the copy states horizontal + replaces the old vertical bar + yards + hunter.

## 4. Mutation proofs — 10 mutations, 10 kills (plus a green control)

Copies under `/tmp/opencode` (`rsync --exclude=Media --exclude=docs --exclude=.git`),
mutated, run against both suites, then deleted.

| # | Mutation | Killed by |
|---|---|---|
| M0 | none (control) | both suites green |
| M1 | default alpha back to 0.85 | appear: "backdrop alpha ships OPAQUE" |
| M2 | migrate every table colour (drop exact-match) | appear: 23 raised on a fresh profile / 10 customs rewritten; options: custom colour preserved |
| M3 | drop the active-preset guard | appear: Classic Retro 0.85 rewritten |
| M4 | drop the once-per-profile early return | appear: "the flag blocks a later re-run"; options: "third run a no-op" |
| M5 | HUNTER default true → false | appear: hunter ON pins; options: "nil hunter value reads ON" |
| M6 | getter falls back to `false` instead of the class default | options: "nil hunter value reads ON" |
| M7 | delete the `set_opts` migration call | appear: wiring pins; options: seeded profile not migrated |
| M8 | flag renamed `_213` → `_212` | appear + options: flag pins |
| M9 | old-default constant alpha 0.85 → 0.86 | appear: 0 raised; options: seeded default not migrated |
| M10 | add `background_color = {0,0,0,1.0}` to a class defaults block | appear: "the HUNTER defaults block overrides no backdrop colour" |

## 5. Residuals / boundaries (stated, not hidden)

1. **Explicit pure black at 0.85 alpha** picked through the colour picker is
   byte-identical to the old default; it becomes opaque. No saved signal distinguishes
   them (the addon has no per-key touched-tracking), so the alternative is to migrate
   nothing.
2. **Classic Retro → then switched to Custom** leaves `{0,0,0,0.85}` with
   `theme_preset = nil`; that also becomes opaque. A profile still *on* Classic Retro is
   protected.
3. **Profile switched mid-session** is migrated at the next login, not immediately:
   nothing in the tree handles `OnProfileChanged` (repo-wide grep: no `OnProfile*`
   handlers outside `Libs/`), and `set_opts()` runs once from `main.lua:424`.
4. **The option copy is ahead of the module.** The description now says "standalone
   horizontal … replaces the old vertical bar"; `weave_range.lua` in this tree is still the
   vertical 16×120 bar left of `PlayerFrame` with a band fallback label. The copy must not
   ship without that lane's module change, or it describes UI that is not there. (The
   toggle key and the hunter default are correct either way.)
5. **Band fallback**: on clients without a point distance reading the label is banded
   ("5-8 yd"), not exact — the copy says so ("exact where the client exposes a distance
   reading, banded where it only has range checks").

## 6. Filed cross-lane items

1. **`tests/run.sh` (orchestrator-owned).** Register the new suite:
   `run "lua5.1 tests/appearance_defaults_state.lua" lua5.1 tests/appearance_defaults_state.lua`
   Until then `tests/toc_check.lua` reports exactly 2 failures, both this pin
   ("unregistered: tests/appearance_defaults_state.lua", "46 registered, 47 on disk").
   Nothing else in toc_check moved (1080 of its 1082 checks pass).
2. **`weave_range.lua:210` (`bars-range-hunter`).** The runtime gate is
   `class_db.weave_range_enabled == true`, while the documented default is now
   `nil == ON for HUNTER`. AceDB's copy makes nil impossible for a normal hunter profile,
   but a hand-built/copied class row can still be nil, and then the toggle shows ON while
   the bar stays hidden. Requested change:
   ```lua
   local enabled = class_db.weave_range_enabled == true
       or (class_db.weave_range_enabled == nil
           and ST.weave_range_default_enabled
           and ST.weave_range_default_enabled(ST.player_class))
   ```
   No other class's semantics change (the helper answers false for them).
3. **Bar geometry/colour options — none shipped, by design.** The new bar needs no new
   widget for this order, and inventing keys no code reads is banned. If the operator
   wants placement/scale later, the keys to add are `weave_range_x`, `weave_range_y`,
   `weave_range_scale` (class-table `input`/`range` widgets read by `weave_range.lua`,
   defaults `0 / -120 / 1`) — proposed only, not implemented.
4. **Not mine, observed in the tree** (lesson: every lane lists every file it changed):
   other lanes were writing concurrently during this session —
   `Libs/LibRangeCheck-2.0/.../LibRangeCheck-2.0.lua` (`cross-client-engine`),
   `main.lua`, `practice.lua`, `practice_ui.lua`, `swing_source.lua`,
   `tests/swing_source_state.lua`, `luac.out` (build artifact), `desks/journal.md`
   (orchestrator), `desks/audit-features/`, `desks/cross-client-engine/`. Snapshot at
   handoff; my five files were untouched by them and their line citations in this report
   were re-verified against the tree at handoff (main.lua:390/392/416/424/795/860,
   bars.lua:183/323/499-526, weave_range.lua:210).

## 7. Owed in-client checks (offline cannot prove these)

1. Fresh profile (or `/st` profile reset): bar backdrop is opaque black, and the coloured
   fill still looks as before on all hands.
2. An existing profile that never touched the colour: backdrop opaque after one
   login/reload; `/fstack`-free spot check on mainhand/offhand/ranged.
3. A deliberately customised backdrop (e.g. Clean Glassmorphic at 0.65): still translucent
   after the same login — the migration must not have touched it.
4. A profile on Classic Retro: backdrop stays 0.85.
5. Hunter: ranged distance bar visible by default after login (no toggle), and hidden
   after explicitly turning it off and reloading.
6. Non-hunter: toggle off by default, on when enabled, survives a reload.

---

# Append 2026-10-25 (later) — ranged-bar copy corrected after the module landed

Supersedes §5.4 (the copy is no longer ahead of the module: `weave_range.lua` is the
standalone horizontal bar). Closes §6.2 (the runtime gate now shares the same nil rule).

## What changed

`option_tables.lua` `weave_range_enabled.desc` replaced with the bars lane's verbatim
replacement (`bench/bars_range_hunter_2026-10-25.md` §6). Getter / setter / `disabled` are
untouched. The old sentence "banded where it only has range checks" was FACTUALLY WRONG
(HU-23: exact yards only, no band fallback); so was "replaces the old vertical bar" — that
bar no longer exists, which is why the sanctioned copy omits it.

Each claim in the new copy verified against the module before shipping:

| Copy claim | Module evidence |
|---|---|
| "full at 5 yd or closer" | `weave_range.lua:63` `NEAR_YARDS = 5`, `fill_fraction` (:137-160) |
| "35 yd band, Auto Shot range" (hunter) | `:65` `HUNTER_FAR_YARDS = 35`, `far_yards_for` (:93-99) |
| "30 yd band" (everyone else) | `:64` `FAR_YARDS = 30` |
| "exact distance in yards" | `:208-213` `format_yards` → `%d yd`, label `"12 yd  IN RANGE"` (:216-218) |
| "MELEE / IN RANGE / OUT" | `:183-189` `state_label` |
| "client cannot answer a distance … hides" | `:420-428` `st.api.UnitDistance` only, non-number → `hide_bar()` |
| "standalone horizontal" | `:76-77` 200×10, own frame `:275-277` |

## Pin added (`tests/options_load_state.lua` §29)

The desc must not carry the stale source claim — `"banded"`, `"range check"`,
`"librangecheck"` all absent — must say "exact distance" and name
`MELEE / IN RANGE / OUT`; and the band numbers are read out of `weave_range.lua`
(`NEAR_YARDS` / `FAR_YARDS` / `HUNTER_FAR_YARDS` = 5 / 30 / 35) and each must appear in the
desc. That binds copy to code, so a module retune or a copy edit reds the same pin.

**Conflict, stated not hidden:** the follow-up asked the pin to reject the substring
"band" as well, but the mandated copy itself says "35 yd band" and "30 yd band". The pin
therefore rejects the defect wording ("banded" / "range checks" / the library name), not
the range-window noun "band". If the operator wants the word gone entirely, the copy must
be reissued by its owning lane.

## Verification

- `lua5.1 tests/options_load_state.lua` → **3606 checks, 0 failed** (was 3596; +10)
- `lua5.1 tests/appearance_defaults_state.lua` → **145 checks, 0 failed**
- `luacheck option_tables.lua tests/options_load_state.lua` → 0 warnings / 0 errors
- Mutations on `/tmp/opencode` copies (deleted after):
  - M-A reintroduce `"…, banded where it only has range checks, …"` → 2 FAIL
    ("no stale 'banded' fallback wording", "claims no range-check source").
  - M-B `HUNTER_FAR_YARDS = 35` → `30` in the module → 1 FAIL
    ("the module's hunter far bound is 35 yd (got 30, want 35)") — the copy/code pin binds.

## §6.2 closed (bars lane)

`weave_range.lua:108-113` `class_default_on(ST)` calls `ST.weave_range_default_enabled(
ST.player_class)`, and `:117-135` `enabled_for` implements true → on, false → off,
nil → class default. The runtime gate and the options toggle now answer identically; the
filed nil-parity request is satisfied.

