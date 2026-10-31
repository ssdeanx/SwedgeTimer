# docs-release — 2026-10-28 wave release notes (2.1.3, no bump)

Desk: `docs-release`. Brief: `bench/briefs/brief_docs-release_2026-10-28.md`.
Verdict: **DONE (prose)**. `CHANGELOG.md` + `README.md` now describe the 2026-10-28 wave inside the
existing `## [2.1.3]` section. Version unchanged (`2.1.3` in all 7 TOCs and `main.lua:5`, none touched),
no new version heading, no in-client claim, and the §P5-3 power-bar sentence is corrected.

Write scope held exactly: `CHANGELOG.md` (CRLF preserved) and `README.md` (LF preserved). No `.lua`,
TOC, test, lint-config, `AGENTS.md`, `TESTING.md`, `docs/`, `Libs/` edit; no git; no other bench or
desk file touched (`bench/docs_release_2026-10-28.md` and `desks/docs-release/` are this lane's own
outputs).

## 1. Gate

- Baseline (before edit): `bash tests/run.sh` → **54 steps, 0 failed**; luacheck **2 warnings / 0 errors
  in 97 files** (`compat.lua:36`, `main.lua:87` — the documented floor).
- Final (after edit): identical — **54 steps, 0 failed**; luacheck **2 / 0 in 97 files**.
- Baseline hashes of the two docs matched the independent audit's manifest exactly, so this lane started
  from the audited text and nobody else edited the docs in between:
  - `CHANGELOG.md` `f0ee54272eb87672238b64154643ee1fb9ae6d9af0b5ecc059e847702194aa4f` (audit §Manifest)
  - `README.md` `abb64897b91a69a99721d34a8e08fcdd760ad49003c9f74df3c77bc55484c699` (audit §Manifest)
- Final: `CHANGELOG.md` `3094c0ea543e81666a302d1e4916451d0a6feb515a6d6834eeb74c176b518e4c`
  (1222 lines, 1222 CRLF); `README.md` `6285a982ddc5025bc8268b2bea749334caaf9b11e9ac805606ba0aaf5f7f4373`
  (147 lines, 0 CR).

**Which test touches the docs (and why it still passes).** Exactly one thing in `tests/` reads a doc:
`tests/toc_check.lua:534-560` pins the `- **The per-class sets.**` passage of `CHANGELOG.md`. It reads
the file, normalises `\r\n` to `\n`, locates the bullet by content (`^%-%s+%*%*The per%-class sets`)
and compares the parsed keys against `classes/*.lua` — never against a line number. That passage is at
`CHANGELOG.md:950`, which this lane did not touch (it moved only because the 2.1.3 section grew: 902 →
950). No suite reads `README.md`. Nothing else in the harness consumes prose, so a prose-only change
cannot move the step count; the re-run confirms it.

## 2. What was written

### CHANGELOG.md — `## [2.1.3]` extended in place

| Subsection | Change |
|---|---|
| Added | **changed** the power-bar bullet (see §3); **added** `Melee pair height` (one control sizes MH+OH, 6-60 px, clearing returns each hand's own height, offhand Height/Width locked and showing the rendered size) and a `/st diag` bullet (per-hand BAR STATE + power line + `why=`/gate/receipt fields + quarantine line) |
| Changed | **added** the activity gate (offhand/ranged show on a real offhand swing or a real shot, or while Auto Shot armed; window ~2 cycles clamped 1.5-8 s; combat+target alone no longer shows them; the configured show rule still applies on top); **added** the one-time forced ranged placement (every ranged-owning class, dragged/scaled row included, no write/notice when already in place, post-pass drag respected, power row reserved); **added** the offhand sizing invariant; **rewrote** the old hunter-only shot-restart bullet into the generic `preventSwingReset` guard + Shoot/Throw/Shoot Wand removed from the addon's melee-reset list, with the Wrath/Cata library residual kept |
| Fixed | **added** the hunter queue-tint melee-cycle gate and its four clear paths (defaults unchanged: Raptor ON, Steady OFF); the Classic Era `CR_HASTE_SPELL` / `GetCombatRating(20)` crash; the opaque-backdrop migration now reaching a saved profile (`rawget` + `== true` marker); the hunter cast bar / range helper / proc badges painting while the ranged bar is hidden |
| Hardening | **added** the AceDB defaults-metatable read hardening (`rawget` + type checks across the class table, sound channel, latency/GCD/bar-full-delay keys, migration marker, placement latch); the sound containment (string channel, `"Master"` fallback, `pcall` on play/stop, corrupt cue choice falls back); **added an explicit offline-only disclaimer** for the whole 2026-10-28 wave; kept the existing audits bullet |

### README.md

- Replaced the power-bar paragraph: the bar now sits **in the slot under the melee stack** and follows
  the **offhand row** even while that hand is idle (mainhand row otherwise), hides with no melee bar on
  screen; added the offhand-takes-mainhand-size rule and **Melee pair height**; kept the hunter stack
  sentence.
- Added a second short paragraph: offhand/ranged are activity-driven (real swing/shot, not combat) and
  the ranged row is placed once at the first login after updating, with post-update drags respected.
- Extended the `/st diag` line: it now carries a per-hand bar-state line, the power-bar state and a
  guard-quarantine line.
- Left `README.md:103` (Opaque Bar Backdrop) alone deliberately: it was **false before this wave** (the
  migration could never run — `config.lua` read the marker through AceDB's `'**'` metatable) and the
  appearance-fix makes it true. Nothing to change; the sentence is now honest.

## 3. The corrected §P5-3 power-bar sentence

The audit (§P5-3) found `CHANGELOG.md:33-36` contradicted `power_bar.lua:206-232`: the offhand **ROW**
owns the slot even while that hand is idle, not "offhand when used".

- was: "a thin primary-resource bar under the bottom-most visible melee swing bar (offhand when used,
  else mainhand), anchored at that bar's width."
- now: "a thin primary-resource bar in the slot under the melee stack. It anchors to the **offhand
  row** whenever the class can use an offhand — even while that hand is idle and hidden — otherwise to
  the mainhand row; it re-points when the owning row is moved, and it hides when no melee bar is on
  screen."

Verified against the tree, not just the audit: `power_bar.lua:16-25` (PLACEMENT header), `:141-149`
(`pb.anchor_choice`), `:186-189` and `:212-225` (`choose_anchor`/`usable_hand_frame` — visibility is
deliberately not the trigger; the rect change is), `pb.MIN_HEIGHT/MAX_HEIGHT = 10/30` (`:57-58`).

## 4. Evidence map — audit MUST-CLAIM → what the notes say

| §P5-3 must-claim | Evidence read for this lane | Where in the docs |
|---|---|---|
| 1. activity-driven offhand/ranged, 2-cycle window 1.5-8 s, combat alone no | `main.lua:2804-2806` (`HAND_ACTIVITY_CYCLES/ MIN/ MAX`), `:2843-2847`, `:2862` (`auto_repeat_active`), `:2972/:2981` (show rule then gate); `bench/bars_decouple_2026-10-28.md` §1/§3 | CHANGELOG Changed #1; README ¶2 |
| 2. ranged row normalised once, every ranged-owning class, dragged/scaled included, one notice, later drag respected, power row reserved | `bars.lua:358` (`ranged_placement_213`), `:362` (`RANGED_PLACEMENT_VERSION = 2`), `:368` (gap), `:524` (version latch); `bench/ranged_forced_2026-10-28.md` §S2-S6 (SUPERSEDING) | CHANGELOG Changed #2; README ¶2 |
| 3. one melee pair height; clearing restores each hand; offhand at mainhand width AND height; offhand Height locked/mirrors | `option_tables.lua:7303` (`min = 6, max = 60`), `:7210-7275` (offhand Width locked + routed), `:7285-7294` (offhand Height follows); `bars.lua:274-330` (`melee_pair_height` rawget, `hand_bar_size`, offhand pair branch); `bench/layout_finish_2026-10-28.md` §3, `bench/ui_truth_diag_2026-10-28.md` §1 | CHANGELOG Added #8/#9, Changed #3 |
| 4. hunter stack unchanged; queue tint only on a live MH cycle, cleared on consume/combat-exit/target change; defaults unchanged | `classes/hunter.lua:163` (`hunter_mainhand_cycle_live`), `:1246-1252` (`maintain_queue_tint`), `:1289`, `:1434`; `bench/hunter_tint_2026-10-28.md` §2, §4 (Raptor ON, Steady OFF) | CHANGELOG Fixed (hunter fill) |
| 5. power bar in the slot under the melee stack, offhand ROW even idle, else mainhand, hides with no melee bar, 10-30 px | `power_bar.lua:16-25`, `:141-149`, `:186-189`, `:212-225`, `:57-58`; `bench/bars_decouple_2026-10-28.md` §1 | CHANGELOG Added power bar; README ¶1 |
| 6. `/st diag` per-hand BAR STATE (+ queue flags) | `diag.lua:707` (bar line format with `why/gate/active/win/left/src`), `:918-919` (power line), `:947-996` (quarantine); `bench/layout_finish_2026-10-28.md` §5, `bench/ui_truth_diag_2026-10-28.md` §2 | CHANGELOG Added `/st diag`; README slash-command line |
| 7. sound: string channel, `"Master"` fallback, playback pcall'd, twist cue + options preview | `classes/paladin.lua:1152-1177` (rawget + type gate + pcall); `bench/paladin_sound_2026-10-28.md` §3-§5, `bench/widgets_guard_2026-10-28.md` §2-§3 | CHANGELOG Hardening (sound) |
| 8. Era `COMBAT_RATING_UPDATE` no longer raises; class-table/settings reads no longer materialise AceDB tables | `LibGlobalCooldown.lua:23-46`, `:102`, `:177-182` (literal 20 + pcall + nil-means-unknown) — audit §B1; `main.lua:247` (`rawget`), `classes/paladin.lua` rawget sites, `bench/latent_trap_hardening_2026-10-28.md` L1-L5, `bench/appearance_fix_2026-10-28.md` §2 | CHANGELOG Fixed (Era crash, migration) + Hardening (AceDB reads) |

Also covered from the brief's lane list: `weave_range` distance-bar behaviour was **not** described (it
is untouched and out of scope — `bench/layout_finish_2026-10-28.md` §4/L4), and no new Retail/class
support is claimed anywhere.

## 5. Claims deliberately excluded, and why

1. **Any in-client verification.** Nothing in this wave has been proven in a client (audit §G). The
   notes say "proven by the offline suites and source review only — the in-client pass on TBC Anniversary
   and Classic Era is still owed" (Hardening, last bullet). No CAS/`UNCONFIRMED`-in-client language was
   used to imply the opposite.
2. **"A dragged ranged row survives the first login."** MUST-NOT: it is moved once; only post-update
   drags are kept. The notes state exactly that, and add "a row already in place is left untouched (no
   write, no notice)".
3. **`Show: Always` overriding the activity gate** (HU-38 D1, open operator ruling). Not mentioned at
   all. The notes say only that the configured show rule still applies on top of the gate — true and
   ruling-neutral.
4. **A "no writes on a fresh profile" promise** (audit §P3-5: the latch field is written on the first
   login of every profile/class). The notes say "no write" only for a row that is already in place,
   which is what the pins prove (`bench/ranged_forced_2026-10-28.md` §S3/S5: 0 field writes on a fresh
   row).
5. **"never changed again"** (audit §P3-4 overclaim). The notes say "placed once", not "never again".
6. **The offhand Width slider "changes the offhand bar".** It is now locked and routed to the mainhand,
   so the notes claim only that it shows the rendered size and is locked (the audit's own "fix or lock
   it first" condition is met by `bench/ui_truth_diag_2026-10-28.md` §1).
7. **Vendored-swing-library fixes (HU-29), parry/extra-attack behaviour, protected range checks
   (HU-23).** Explicitly kept: "The library itself stays stock", and the Wrath/Cata reset entries remain
   a stated residual. The hunter ranged-distance bar bullet is unchanged and still says exact yards.
8. **Cataclysm/Mists support, any version bump.** No mention, no number change; the README table still
   marks them "not a supported client".
9. **Retail-only class option getters (audit §P1-2, MONK/DH/EVOKER can raise).** No Retail class or
   class-option claim was added anywhere; the six-class README table is untouched.
10. **`weave_range` "pops up while meleeing"** — untouched widget, operator ruling says leave it
    (`bench/layout_finish_2026-10-28.md` U7). Saying nothing.

## 6. Two MUST-NOT items I treated as overtaken — flagged for the reviewer

The audit was written at 05:48 local; two lanes landed **after** it, and the brief (written 06:35)
lists both in the wave scope. I judged these MUST-NOT bullets superseded by later evidence, and said so
here rather than silently dropping the two user-visible fixes:

- **HU-37** ("do not claim the hunter cast bar / range helper / Rapid Fire bar / badges work while the
  ranged bar is hidden"). `bench/hunter_ui_driver_2026-10-28.md` (06:34) fixes exactly that: the set is
  driven from the hand's anchor frame (`hunter_ui.lua:262-367`, `:671`), with hidden-bar paint pins and
  mutations M1/M2 killed. I claimed it as a Fixed bullet, in offline terms only. If the reviewer prefers
  the audit's stricter reading, deleting that one bullet is enough — no other bullet depends on it.
- **E1** ("do not claim the offhand Width slider changes the offhand bar"). `bench/ui_truth_diag_2026-10-28.md`
  (06:30) locks it and routes writes to the mainhand. The notes do **not** claim it changes the offhand
  key; they claim the lock + the rendered number. That is the audit's own remedy.

Everything else in the MUST-NOT list is honoured as written (§5 items 1-3, 7-8).

## 7. Open items for the operator (not release-note material, recorded here)

- The in-client pass on TBC Anniversary + Classic Era is still owed for the whole wave (audit §G).
- HU-37 and E1 are fixed/proven offline only; their rendering and routing need the client.
- Wrath/Cata residual: the vendored library's own `reset_swing_spells` lists still restart melee on
  Auto Shot/Shoot/Throw there — documented in the notes, not fixed (`bench/bars_decouple_2026-10-28.md`
  U4).
- Audit §B1: the `LibGlobalCooldown.lua` Era fix still has **no test pin and no desk report** (the audit
  verified it from source). I described it in Fixed because §P5-3 explicitly requires it; a pin is still
  owed by whoever owns that file.
- `melee_bar_height` applied live *after* the one-shot ranged pass can re-collide the ranged row with a
  taller melee band until the user drags it (`bench/ranged_forced_2026-10-28.md` V5) — unmentioned in the
  notes on purpose (an edge, not a promise).

## 8. Trail

- Desk: `desks/docs-release/journal.md` (+ done signal in `.signals/`).
- Files written: `CHANGELOG.md`, `README.md`, this report, the desk journal, the signal.
- No git, no lint-config change, line endings verified per file (CRLF for the changelog, LF for the
  README), version 2.1.3 everywhere.
