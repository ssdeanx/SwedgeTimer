# buildout hunter — 2026-10-17 (round 1)

Desk hunter, brief `bench/briefs/brief_hunter_2026-10-17.md`. Scope held:
`classes/hunter.lua`, `hunter_guide.lua`, `hunter_ui.lua`, `hunter_window.lua`,
`tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
`tests/hunter_window_state.lua` only. No git. No lint-config changes. No `_` renames,
no unused-variable work. Line endings preserved per file (`classes/hunter.lua` +
`hunter_guide.lua` CRLF, the rest LF; verified with `file` + a `\r` byte count).
Nothing committed; all changes sit in the tree.

## 0. Previous attempt: what was kept, what was finished

The dead attempt's partial edits were inspected first:

| Partial | Verdict | Action |
|---|---|---|
| `hunter_window.hold_seconds` (H1 kernel) | correct, unused, untested | kept verbatim; header list line added; now consumed by the cast-bar window face and pinned by a new window-suite section |
| `hunter_guide` rule 2b (H4 range gate) | correct, untested | kept verbatim; pinned by a new guide-suite block |
| `hunter_guide` H2 lust suppression (`lust_remaining` input, rules 6a/6b) | correct, no producer | kept verbatim; the producer (gather wiring) + a new guide-suite block added |
| `classes/hunter.lua` | untouched | built here: H2 gather, FD, Readiness |

`hunter_guide.lua` was not edited further this round.

## 1. Changes

### classes/hunter.lua
1. **H2 producer** (`LUST_RESCAN_INTERVAL`, `lust_ids`, the gather block at
   ~line 1054-1083): `inputs.lust_remaining` written on every gather call.
   - `st.api.scan_player_aura` (frozen C2 contract, `bench/buildout_compat-bl_2026-10-17.md` §2)
     over `st.lust_spell_ids` (2825/32182, converted once with `get_tab`).
   - Family gate `st.lust_supported` (Era/UNKNOWN never arm — no scan is spent).
   - 0.5 s throttle (`self.hunter_lust_at` / `self.hunter_lust_remaining`, the paladin
     P3 shape): the cached value is a plain remaining read; only a positive remaining
     arms the window. Absent compat surface / aura API → nil (never zero).
2. **Feign Death** (`FEIGN_DEATH_ID = 5384`, `on_spellcast_succeeded` ~line 279):
   clears the class-owned ranged display state (`auto_repeat_active`,
   `hidden_window_start/duration`, `synced_duration`, `last_restart_at`). The
   engine-owned `start/ends_at/speed` are never touched (bars.lua's OnUpdate runs
   arithmetic over them); the swing engine re-anchors on its own FD path (vendored
   LibClassicSwingTimerAPI 5384 block; swing_source has no FD path).
3. **Readiness** (`READINESS_ID = 23989`, ~line 300): calls
   `st.hunter_ui.force_rapid_fire_refresh` (guarded) — the reference's
   `ForceHunterRapidFireRefresh` translated to this architecture (throttle bypass).

### hunter_ui.lua
4. **H1 consumer**: the cast-bar window face label now counts through
   `st.hunter_window.hold_seconds` (line 614) — same value as before, kernel-backed.
5. **Safe-to-move cast zone** (verify_bank §5.1; `create_cast_zone` line 264,
   `ui.update_cast_zone` line 681): a right-anchored zone texture + 3 px threshold
   marker on the ranged bar's visuals frame, width = `cast_window / cycle * bar_width`,
   green/red from `hunter_window.is_stopped_position_safe` over main.lua's movement
   state. Gate: `hunter_cast_zone_enabled == true` (nil = off).
6. **H6 pet badges** (`create_badge` line 288, `update_bw_badge` ~line 916,
   `update_frenzy_badge` ~line 962, `ui.update_pet_badges` line 1009):
   - BW duration badge: player aura 19574 (or the localized name), countdown text
     (`%.0f` at/above 3 s, `%.1f` below — the reference durationText rule), gold glow
     inside the final 4 s.
   - Frenzy stacks badge: pet aura 19615 (or name), stack-count text (whatever the
     client reports; no fabricated 1).
   - Both: 20 px icons with client spell textures, option-gated nil=off, scans
     throttled to 0.2 s, anchored in a row continuing the aspect icon's fallback
     chain (aspect icon → range helper → bar).
7. **Readiness consumer**: `ui.force_rapid_fire_refresh` (line 1167) clears the RF
   scan throttle.
8. `ui.hide_all` / `ui.update` extended for the new widgets.

### hunter_window.lua
9. Header ported-list line for `hold_seconds` (the function itself was the kept
   partial). No other change.

### Tests (+138 checks: 1571 → 1709)
- `hunter_window_state.lua` 196 → **213**: new §9b hold_seconds (edges, nil/junk,
  kernel-vs-display bounds agreement).
- `hunter_state.lua` 394 → **448**: §13b FD clear + Readiness force (incl. the
  no-ranged-state and no-hunter_ui no-op paths); §14c off-gate extended with the
  three new toggles; §14h cast-zone geometry/colour ladder/marker/off-gate;
  §14i BW + Frenzy badges (countdown formats, glow window, throttle, count text,
  off-gates); §14j Readiness force through the real ui.
- `hunter_guide_state.lua` 981 → **1048**: rule 2b block (nil/0/1/true/false, ahead
  of TBC + Wrath priorities and of rule 7, behind rule 1); H2 suppression block
  (positive-only, Steady spam cue, other rules unaffected, Wrath unaffected);
  gather-wiring block (TBC arms, Heroism by id, throttle window, dropped/expired
  aura, unrelated aura, Era spends zero scans). Sandbox gained a `UnitAura` stub +
  `aura_queries` counter (nil player auras → every old fixture unchanged).

## 2. Evidence

- Focused suites on the real tree: `hunter_state` **448 checks PASS**,
  `hunter_window_state` **213 PASS**, `hunter_guide_state` **1048 PASS**.
- `luacheck` on the 7 touched files: **0 warnings / 0 errors**. Repo total: **0 errors
  on every run** while other lanes were writing (warnings drifted 47–59 in 71 files as
  lanes landed; hunter files contribute zero either way).
- Full harness at hand-off: the tree was a moving target (parallel lanes writing);
  every hunter step was green on every run — syntax, `hunter_state`,
  `hunter_window_state`, `hunter_guide_state`, `guide_contract`, `toc_check`,
  `wiring_check`, luacheck. The failing steps observed during hand-off were all
  other-lane work: `smoke` (classes/druid.lua:116 crash — druid lane), `bars_state`
  (PALADIN/WARRIOR/DRUID count drift + a glow check, plus the expected HUNTER count
  rows below — reconcile wave), `hud_state` (druid slot count), `designmode_state`
  (bars.lua `register_zone`/`new_pips` — bars lane), and intermittently
  `weave_state`/`shaman_state`/`wiring_check` (`ST.SHAMAN.resolve_lava_burst` dead
  hook — shaman lane). None touch hunter files.
- Mutation proofs on `/tmp/opencode/mut_hunter/` (disposable copy; baseline on the
  copy 213/448/1048 green):
  1. `hold_seconds` tail `window_end - now` → `now - window_start`:
     `hunter_window_state` → 3 FAILs (at-start, closing-edge, kernel-vs-display).
  2. rule 6b's `and not lust_window` removed: `hunter_guide_state` → 1 FAIL
     ("the Multi weave suppressed, Steady Shot becomes the spam cue").
  3. FD's `ranged.synced_duration = nil` line removed: `hunter_state` → 1 FAIL.
  4. cast zone `self.is_moving == true` → `~= true`: `hunter_state` → 5 FAILs
     (the colour ladder).
  5. `BADGE_GLOW_WINDOW` 4 → 3: `hunter_state` → 1 FAIL (glow window).
  All five restored; every touched file `diff`-identical to the repo afterwards;
  the copy suite green again (213/448/1048).
- External ids (scraped 2026-10-17, webfetch; Firecrawl search was non-functional):
  wowhead TBC `spell=19574` (BW: 18 s buff / 2 min CD), wowhead TBC + WotLK
  `spell=19615` (Frenzy Effect: 8 s, +30% melee attack speed), wowhead TBC
  `spell=23989` (Readiness: instant, 5 min CD). FD 5384: reference
  `SuperSwingTimer_State.lua:893` + the vendored lib's `reset_swing_spells[5384]`.

## 3. H3 — NOT BUILT; the manual toggle spec for the options pass

Decision stands (verify_bank §4.4 correction): no multi-target counting this round —
nameplate/tab-target counting is unreliable in raids and secret-value-risky on the
mainline engine. The manual fallback to be wired by the options pass:

| Field | Value |
|---|---|
| key | `hunter_multi_target` |
| type | toggle |
| label | "Multi-target mode (manual)" |
| tooltip | "Treat the fight as 2+ targets: the guide prefers Multi-Shot over the single-target filler. Manual because automatic target counting is unreliable in raids." |
| nil-safe read | `db.hunter_multi_target == true` enables; nil = OFF |
| suggested default | false (owner flips per fight) |
| intended consumer | gather writes `inputs.multi_target`; the engine (future round) prefers Multi over Aimed/Steady when `multi_known` and off cooldown, behind rules 1/2/2b — a frozen-contract change, so it ships with its own test wave |
| no keybind/slash this round | the toggle alone is the H3 definition |

## 4. Option defaults for the options pass

Three new user-visible keys ship nil-safe with **nil = OFF** this round (no
default-visible change without an explicit gate); suggested defaults once the owner
verifies in-client:

| Key | Suggested default | Widget |
|---|---|---|
| `hunter_cast_zone_enabled` | true | toggle, HUNTER visual section ("Movement-safe cast zone") |
| `hunter_bw_badge_enabled` | true | toggle ("Bestial Wrath badge") |
| `hunter_frenzy_stacks_enabled` | true | toggle ("Pet Frenzy stacks") |
| `hunter_multi_target` (H3) | false | toggle, see §3 |

H2/FD/Readiness add **no** toggles: H2 rides the guide's own `nextaction_enabled`
(default false, unchanged), and FD/Readiness are event-side correctness with no
display of their own.

## 5. bars_state reconcile counts (report-only, per the round rule)

The hunter widget set grew by: **+2 frames** (BW badge, Frenzy badge), **+6 textures**
(cast zone, threshold marker, BW icon, BW glow, Frenzy icon, Frenzy glow),
**+2 fontstrings** (BW countdown, Frenzy stack count), +0 lines. New totals for the
HUNTER row of `tests/bars_state.lua` (currently `frames 18 / textures 17 /
fontstrings 11`): **frames 20, textures 23, fontstrings 13, lines 0** (extra_frames
4 → 6; the observed run shows exactly those numbers). No hunter *behavioural* check
in bars_state fails.

## 6. UNCONFIRMED / in-client checks (offline cannot load the addon)

| # | Item | Status |
|---|---|---|
| 1 | Bloodlust/Heroism 2825/32182 aura scan on a real TBC client | ids CONFIRMED (verify_bank §2); the live aura payload is the compat-bl in-client item — re-check after this gather wires it |
| 2 | Era never arms | offline-pinned (`st.lust_supported`); in-client `/dump st.lust_supported` on Era (compat-bl check 1) |
| 3 | Bestial Wrath 19574 | id pre-existing in the repo; wowhead TBC cited. In-client: `GetSpellInfo(19574)` name/icon on 2.5.6/3.80.2; badge countdown vs the buff |
| 4 | Frenzy Effect 19615 | CONFIRMED (wowhead TBC + WotLK: 8 s, +30%); the 1–3 **stack count** is community-sourced only (Blizzard forums / Reddit) — the badge shows whatever the client's `count` reports, no hardcoded cap. In-client: confirm the pet aura's count on 2.5.6 |
| 5 | Readiness 23989 | wowhead TBC + reference Constants.lua:181. In-client: confirm `UNIT_SPELLCAST_SUCCEEDED` carries 23989 and the RF bar re-scans |
| 6 | Feign Death 5384 | reference State.lua:893 + vendored lib. In-client: confirm the class clear fires and the ranged bar re-anchors (classic-line lib; Forever's swing_source has no FD path) |
| 7 | Forever Frenzy variant (wowhead `forever/spell=428728`) | **UNCONFIRMED** (403 on scrape) — deliberately not shipped; the Forever pet badge stays inert until an id is confirmed |
| 8 | Badge geometry/anchoring, cast-zone colours in motion | visual, in-client only |
| 9 | PLAYER_STARTED/STOPPED_MOVING availability on each target client | main.lua phase-1 already registers them; in-client: confirm the zone flips green/red while strafing |

## 7. Deviations / notes for the next desk

- Badge glow is a **static gold alpha (0.35)** at the reference pulse's midpoint
  instead of the reference's sine pulse — same signal, no per-frame colour churn.
- The cast-zone width uses the **bar frame width** (reference parity); the texture
  parents to the inset visuals frame, so the right edge sits one border-width in —
  invisible at the shipped 1 px border, noted for the record.
- The cast-zone update writes `ui.zone_safe = nil` on its disabled/absent paths every
  tick (a plain field write); all visual calls are change-guarded.
- FD deliberately does **not** null the engine-owned ranged fields; see §1.2.
- `hunter_guide.lua` is byte-identical to the dead attempt's partial (rules 2b + the
  H2 suppression + their header docs), now pinned.

## 8. Residual state

- Tree differs from pre-dispatch by: `classes/hunter.lua` (+82 lines; CRLF preserved),
  `hunter_ui.lua` (+384 lines; LF preserved), `hunter_window.lua` (+1 header line),
  the three hunter suites (+138 checks), `desks/hunter/journal.md`,
  `desks/hunter/.signals/20261017T141132Z.json`, this file.
- Nothing committed. Other lanes' in-flight failures listed in §2 are not this
  desk's; the hunter lane leaves its steps green.
