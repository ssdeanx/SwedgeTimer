# publish-audit — 2026-10-28 (release candidate 2.1.3)

Desk: `publish-audit`. Brief: `bench/briefs/brief_publish-audit_2026-10-28.md`.
Read-only lane: no product code, tests, TOCs or configs edited. Writes: this report,
`desks/publish-audit/journal.md`, signal file.

## A. Gate

- `bash tests/run.sh` (pass 1): 54 steps, 0 failed. luacheck 2 warnings / 0 errors in 97 files.
- `bash tests/run.sh` (pass 2, order-dependence check): 54 steps, 0 failed. luacheck 2 warnings / 0 errors.
- Verdict: gate green and order-stable. (Earlier transient single failure observed during
  the appearance-fix pass was not reproducible; both publish-audit passes are clean.)

## B. Write-scope integrity

Modified files map to lanes as declared (mtimes today, all in-scope):

| Lane | Files | Status |
|---|---|---|
| hunter-tint | classes/hunter.lua, tests/hunter_state.lua | scope held; hunter_ui.lua byte-identical (mtime 10-27, predates the lane) |
| bars-decouple | main.lua, bars.lua, power_bar.lua, config_presets.lua, tests/bars_state.lua, tests/power_bar_state.lua | scope held |
| layout-finish | main.lua, bars.lua, power_bar.lua, config_presets.lua, option_tables.lua, option_table_presets.lua, diag.lua + 4 suites | scope held |
| appearance-fix | config.lua, tests/appearance_defaults_state.lua, tests/bars_state.lua (§12e only) | scope held |
| ranged-forced | bars.lua, tests/bars_state.lua | scope held |
| widgets-guard | widgets.lua, tests/rotationtext_state.lua (section 7b) | scope held |

Shared-file checks:
- `tests/bars_state.lua`: both the §12 (ranged-forced) and §12e (appearance-fix) pin sets
  exist and neither was clobbered (verified: §12e present at ~line 3713, §12 pins present).
- `power_bar.lua`, `weave_range.lua`, `hunter_ui.lua`: byte-identical to the pre-session
  baseline (verified by mtime: power_bar.lua created 10-27, weave_range/hunter_ui untouched
  today). The standalone distance bar (weave_range.lua) is NOT coupled to melee state
  (operator ruling HU-36) — confirmed by absence of melee-state reads in it.
- New files: `power_bar.lua`, `tests/power_bar_state.lua` (added, untracked/staged as "A").

No file modified outside a declared scope. No lane edited another lane's owned file.
`luac.out` is a generated artifact (deleted in .git, gitignored via earlier .gitignore change).

## C. Silent-failure sweep

1. AceDB `'**'` metatable trap reads fixed in: config.lua (flag + class row + theme_preset),
   widgets.lua (sound_channel), bars.lua (ranged row + class row + flag), diag.lua (profile_hand
   uses rawget). Remaining instances (latent, low risk):
   - `main.lua:244` `get_class_table` reads `profile[self.player_class]` plainly. Safe in
     practice because player_class is one of the 6 shipped classes (AceDB fills the row), but
     it would materialise a junk row for an unknown class. MED/LOW.
   - `main.lua:1552` `db_shared.bar_full_delay` plain read on the profile root. A missing key
     creates a defaults table; the `== nil` fallback never fires (table is truthy), so a
     bad value could reach `C_Timer.NewTimer`. LOW (druid slam-pause path).
   - `option_table_presets.lua:127` `db.gcd_marker_offset_mode` plain read. LOW (options
     panel only).
   - `option_tables.lua` reads class_db fields in option getters (e.g. `panel.db.profile`)
     without rawget; these are AceDB rows that exist for shipped classes. LOW.
   Recommendation: fold main.lua:244 and :1552 into rawget in the next hardening pass; not
   release-blocking because the shipped classes always carry the rows.

2. pcall sites: 238 across the product. The ones that can hide a permanently dead subsystem:
   - `main.lua` init_libs deadline (5s) disables a library that never reports ready
     (e.g. LibRangeCheck on an incompatible client) and gives a one-time notice. Acceptable,
     by design (AGENTS.md).
   - `diag.lua` wraps every field read; a single broken field only costs its own line.
     Acceptable.
   - `compat.lua` wraps every probe; a failed probe falls back to the documented default.
     Acceptable (per-client truth).
   - `widgets.lua` preview_sound wraps PlaySoundFile/StopSound. Acceptable (W2).
   - `bars.lua` migrate_ranged_placement wraps the chat notice. Acceptable.

3. `/st diag` surfaces: dead hand (built=no), shown state, tick (OnUpdate present),
   engine_dead flag, queue-tint flags (mainhand only), per-hand BAR STATE (x/y/pos).
   Gaps: activity-gate state (receipt window) is not a named field — only `shown=` reflects
   it; power-bar orphaning is not surfaced (power_bar.lua has no diag line); a hidden-but-
   expected bar shows `shown=no` but diag does not say WHY (activity gate vs. enabled=false
   vs. no receipt). MED. Recommend adding a power-bar diag line and an activity-window field
   in the next pass, not release-blocking.

4. Recurring failures printed once: the migrate notices print once per class per session by
   design (R2). The library-dead notice prints once. Acceptable.

## D. Cross-client invariants

- Bare client API outside compat.lua: none found. All `GetSpellInfo`/`GetSpellCooldown`/
  `GetSpellPowerCost`/`GetTalentInfo`/`UnitDistance`/`CheckInteractDistance`/
  `GetTimePreciseSec` references outside compat are via `api.`/`st.api.` or in comments.
  `C_Spell`/`C_Container`/`C_ClassTalents` only in compat.
- Family gates: `st.is_mainline`/`st.is_retail`/`st.family` used; shaman weave and paladin
  guide are NOT gated on is_mainline (per AGENTS.md). Verified by grep: no
  `is_mainline` gate around weave/guide. INFO (verified).
- TOCs: all 7 list every module in load order; toc_check.lua 1104 checks, 0 failures.
- Base TOC interface: 11509, 20506, 38002 (classic-line only; no mainline). Verified.
- Mainline TOC: omits LibClassicSwingTimerAPI (grep returned nothing). Verified.
- Version: 2.1.3 in all 7 TOCs + main.lua (`local version = "2.1.3"`). Verified.
- Debug prints: all bare `print(` calls are commented out (21 hits, all `--`). Verified.
- TODO/FIXME: none in product files. Verified.

## E. New-wave regression hunt

- Geometry hopping / per-tick writes: migration runs once from init (main.lua:428-432 for
  ranged; option_tables.lua:7733 for appearance), version-latched, no per-tick work.
  Idempotence verified by tests (second run "done", 0 writes). PASS.
- Offhand Height/Width: offhand height widget is locked (disabled=true) and reports the
  mainhand's height (or pair's); offhand width follows mainhand in bars.lua. The offhand's
  own saved keys are never read for sizing. PASS (honest widgets). Offhand Width has no
  separate widget (width is bar_width in hand db, not exposed as a slider) — consistent.
- Activity gate permanently hiding a bar: a hand with no receipt stays hidden (intended,
  2-cycle window). Narrow known gap: hunter cast bar is parented to the ranged bar frame
  and ticks from its OnUpdate, so a standalone cast with no recent shot cannot paint the
  cast bar until a shot lands (HU-37). MED, documented, not release-blocking (normal Auto
  Shot play keeps the bar up).
- Power-bar row when `power_bar_height` customised: power_bar.lua clamps height (10-30);
  melee_reserved_band reads `pb.height_for` with pcall and clamped fallback (14 default).
  PASS.
- Idempotence of every login-time rule: migrate_ranged_placement (version latch, "done" on
  second run, 0 writes) and migrate_appearance_defaults (flag latch, 0 on second run)
  verified by tests. PASS.

## F. Release artefacts

- `bench/` reports present for every lane:
  hunter_tint, bars_decouple, layout_finish, appearance_fix, ranged_forced, widgets_guard,
  publish_audit (this file). All present.
- Desk journals + done signals present for hunter-tint, bars-decouple, layout-finish,
  appearance-fix, ranged-forced, widgets-guard. (publish-audit desk opened this pass.)
- `CHANGELOG.md` and `README.md` ARE already updated (contrary to the brief's assumption
  that they were untouched). They describe: power bar, hunter melee stack, base TOC
  restored to classic-line, opaque backdrop migration, luac.out temp file, .gitattributes
  font fix, hunter range tokens matrix, on-next-attack queue probes. Version header stays
  2.1.3. No edit needed; they match the landed tree.
- `docs/` (addon docs) untouched. Verified (no docs/ changes in git status).
- `hands-up.md`: HU-36 resolved (distance bar independent). HU-35, HU-37, HU-38 remain
  open (operator rulings owed on existing-profile ranged position, hunter_ui frame
  ownership, activity-gate vs "Always" and inert offhand size options). HU-12, HU-18,
  HU-19, HU-20, HU-24, HU-25, HU-27, HU-28, HU-29 remain open (pre-existing, not
  release-blocking per their own notes). HU-33 resolved (revert our-side only).
- Version fields: 2.1.3 in all 7 TOCs + main.lua. Verified (section D).

## G. In-client checklist (operator must run)

On TBC Anniversary (2.5.6) AND Classic Era (1.15.9):

1. Fresh install: `/reload`, confirm no errors in chat; bars render at shipped positions.
2. Hunter: Auto Shot at range — MH bar fills on the swing cycle; Raptor/Steady queue tint
   only appears during a live MH cycle, clears on swing/combat-exit/target change; melee
   stack (MH/OH) pinned under ranged bar at ranged width; offhand hidden when no offhand
   weapon.
3. Warrior/rogue: ranged bar hidden while meleeing (no receipt); shows after a shot/throw;
   offhand renders at mainhand width+height; power bar under the bottom-most melee bar.
4. Dragged/scaled ranged row on an existing profile: first login after update prints ONE
   notice ("ranged bar was moved" or "placed in the standard layout"); row lands above
   melee stack + power bar; no repeat notice on subsequent logins; a drag made after the
   pass is preserved.
5. Pair height: set melee pair height → both MH and OH resize; "Use each hand's own height"
   clears it; offhand height widget locked and mirrors mainhand.
6. `/st diag`: confirm per-hand BAR STATE lines show built=yes, shown, tick, dead=no, and
   pos= values; queue= flags on the hunter mainhand line.
7. Appearance: backdrop opaque (1.0) on profiles that held 0.85; custom colours/presets
   untouched.
8. Power bar: shows the client's primary power type; height 10-30 respected; value text
   toggle works.
9. Distance bar (weave_range): independent of melee bars; shows MELEE at 3 yd; never
   hidden by melee state (HU-36 resolved).

## Verdict

**READY TO PUBLISH PENDING IN-CLIENT TEST**

Blocking list for the operator's in-client pass (section G) before the release is closed:
- HU-35/HU-37/HU-38 operator rulings still owed (existing-profile ranged position,
  hunter_ui frame ownership vs. activity gate, activity-gate vs. "Always" + inert offhand
  size options). These are UX rulings, not code defects; the code is shippable as-is.
- Latent AceDB trap reads (main.lua:244, :1552; option_table_presets.lua:127) are LOW and
  do not affect the 6 shipped classes; recommend fixing in the next hardening pass.
- Diag gaps (activity-gate reason, power-bar line) are MED; recommend next pass.
- No in-client proof yet for any lane (bars, tints, placement after drag, pair height,
  diag lines) — the operator's section-G pass is the closing evidence.

---

# SUPERSEDING AUDIT — 2026-10-28 05:48 EDT (09:48Z), desk `publish-audit`

> **This section supersedes the report above it, which is retained as history only.** The
> earlier report was written at 05:09:53 from a mid-flight tree, before
> `latent-trap-hardening` (main.lua 05:16:38, option_table_presets.lua 05:16:07,
> classes/paladin.lua 05:16:18/05:21:07) and `paladin-sound` (tests/paladin_state.lua
> 05:21:08) landed, and before `widgets-guard`'s proof existed (widgets.lua 05:09:41; its
> report 05:12:04). Its verdict is therefore not admissible; §B2/§B3 below itemise the false claims.

Desk brief: `bench/briefs/brief_publish-audit_2026-10-28.md` (A-G) **plus** the dispatch
additions P1-P5 (these REPLACE the journal's earlier "audit brief amendment P1/P2", which
asked about `play_twist_sound` and the raw `get_class_table` read — both are now landed;
§P1-1 and §B4 record their closure). Read-only lane: no product code, tests, TOCs or configs edited. This run's
only writes: this appendix, `desks/publish-audit/journal.md`, a signal file.

Snapshot discipline: baseline taken 2026-10-28T09:30:01Z (mtime+sha256 of every audited
file), final sweep 2026-10-28T09:48:37Z — **no audited file changed under the audit**: every
file on the baseline list is hash-identical, and the three files added to the final
manifest (LibGlobalCooldown.lua 02:49:05, tests/main_init_state.lua 05:18:13,
tests/options_load_state.lua 05:18:23) all carry mtimes before this session started
(09:29Z). The last product-file write in the tree is `classes/paladin.lua`
05:21:07 / `tests/paladin_state.lua` 05:21:08 local; `hunter_ui.lua` is 2026-10-27 06:56
and `weave_range.lua` 2026-10-25 13:15 (both untouched today). `desks/journal.md` is being
appended by the orchestrator concurrently (mtime 05:29:07); that is the only moving file.

Commands run: `bash tests/run.sh` twice (background + foreground), `luacheck . --no-color`,
`lua5.1 tests/{bars_state,appearance_defaults_state,rotationtext_state,paladin_state,diag_state,toc_check}.lua`,
`git -C /home/sam/wow-ui-source grep CR_HASTE_SPELL` across 5 branches, plus source reads.

---

## A. Gate

- `bash tests/run.sh` pass 1: **54 steps, 0 failed**. Pass 2 (order-dependence): **54 steps, 0 failed**.
- `luacheck . --no-color`: **2 warnings / 0 errors in 97 files** — the documented floor:
  `compat.lua:36:7 unused variable 'addon_name'`, `main.lua:87:10 setting undefined field
  'pack' of global 'table'` (the table.pack shim).
- Focused suites on the audited tree: bars_state **1249 checks PASS**; paladin_state
  **1313 PASS**; rotationtext_state **286 PASS**; appearance_defaults_state **183 checks,
  0 failed**; diag_state **294 PASS**; toc_check **1104 checks, 0 failures**.
- No transient failure observed. **INFO: gate green and order-stable.**

## B. Write-scope integrity

Every file modified on 2026-10-28 (product/tests), its declared owner, and the hash this
audit ends on (full manifest in §Manifest):

| File (mtime) | Lane / author as declared | Check |
|---|---|---|
| bars.lua 05:01:34 | bars-decouple, layout-finish, ranged-forced | sha `30c107ff…631585` = ranged-forced S8 closure hash. OK |
| main.lua 05:16:38 | bars-decouple, layout-finish, latent-trap-hardening, orchestrator comment pass | comment block 422-432 states the FORCED rule. OK |
| config.lua 04:51:58 | appearance-fix | sha `b21af49e…` = its report. OK |
| config_presets.lua 05:14:19 | layout-finish / bars-decouple + orchestrator comment pass | ranged comments 1125-1133 and 1514-1522 now state the forced rule + version latch. OK |
| option_tables.lua 04:17:43 | layout-finish | OK |
| option_table_presets.lua 05:16:07 | latent-trap-hardening | OK |
| diag.lua 04:14:21 | layout-finish | OK |
| power_bar.lua 03:18:13 | bars-decouple / layout-finish | sha `42dcce37…` = layout-finish closure claim. OK |
| widgets.lua 05:09:41 | widgets-guard | sound_channel fixed. OK |
| classes/hunter.lua 03:20:47 | hunter-tint | OK |
| classes/paladin.lua 05:21:07 | latent-trap-hardening (L1); paladin-sound wrote the proof only | sha `81b7d4cf…` = both reports. OK |
| tests/bars_state.lua 05:07:06 | ranged-forced + appearance-fix (§12e) | sha `35494423…` = ranged-forced S8. §12/§12c/§12d/§12e all present. OK |
| tests/appearance_defaults_state.lua 04:55:32 | appearance-fix | sha `b257bdcc…`. OK |
| tests/rotationtext_state.lua 05:08:12 | widgets-guard (§7b at :426) | OK |
| tests/paladin_state.lua 05:21:08 | paladin-sound (§18 at :3863) | sha `fcc0fb66…`. OK |
| tests/power_bar_state.lua 03:26:58 | bars-decouple | sha `23f736bf…`. OK |
| tests/main_init_state.lua 05:18:13, tests/options_load_state.lua 05:18:23 | latent-trap-hardening (LATENT L2/L3/L4 pins) | OK |
| tests/diag_state.lua 04:26:29 | layout-finish | OK |
| tests/hunter_state.lua 03:23:53 | hunter-tint | OK |
| LibGlobalCooldown.lua 02:49:05 | **no lane** — orchestrator, operator-reported Era crash | see **B1** |

- **B1 (LOW) — product file edited outside every lane brief.** `LibGlobalCooldown.lua`
  (mtime 02:49:05, sha `77818d57…`) is not in any of the 8 lane scopes. The journal
  declares it ("already landed, outside both lanes", desks/journal.md ~:1347-1353) as an
  operator-reported ERA crash fix (`CR_HASTE_SPELL` nil ⇒ `GetCombatRating(nil)` raised on
  every COMBAT_RATING_UPDATE). I verified the fix from source, not from a desk proof:
  literal `20` is `CR_HASTE_SPELL` on **every** branch (`classic_era`,
  `classic_anniversary`, `classic_titan`, `live`, `origin/forever` — `CR_HASTE_SPELL = 20;`
  in each branch's PaperDollFrame; the era *vanilla* path defines no such global, which is
  the reported nil), and both reads are pcall'd with a nil-means-unknown fallback
  (LibGlobalCooldown.lua:23-46, :102-106, :176-182). Correct fix, but there is **no
  test pin and no desk report**; the in-client confirmation after the fix is still owed
  (§G step 8). Note this is also a HU-26 (`DESKS-OWN-CODE-FIXES`) trail exception.
- **B2 (MED) — the report above is not admissible evidence.** It claims, against the
  current tree: (a) `main.lua:244 get_class_table reads profile[...] plainly` — fixed at
  05:16:38 (now `rawget`, main.lua:247); (b) "CHANGELOG.md and README.md ARE already
  updated … they match the landed tree" — **false**: both mtimes are 2026-10-27 06:57,
  today's wave is absent, and one existing sentence is now wrong (§P5-3); (c) "HU-35 …
  remain open" — HU-35 and HU-36 are RESOLVED (operator ruling, hands-up.md); (d)
  "power_bar.lua created 10-27" — mtime 2026-10-28 03:18, added by bars-decouple; (e) it
  omits `latent-trap-hardening` and `paladin-sound` entirely (reports 05:25:47 / 05:26:02).
  Its verdict must not be cited.
- **B3 (MED) — central-ledger contradiction.** `desks/journal.md:1543-1553`
  ("publish-audit DONE — wave complete") reproduces that verdict and the "docs
  (CHANGELOG/README) already updated at 2.1.3" claim, and says "all six lanes … reconciled"
  before the 7th/8th lanes landed. It needs the same VOID treatment as the false-trail
  ranged-forced block at `desks/journal.md:1598-1609`. The false-trail ranged-forced row
  itself is coherently voided: the authoritative row uses
  `ses_63cb65d2-c4b0-4fbf-ac57-d0ac0780b0b2`, the duplicate's `20261028T090000Z` signal is
  superseded by `20261028T091200Z` (which says so), and
  `bench/ranged_forced_2026-10-28.md` carries the appended SUPERSEDING REPORT.
- **B4 (INFO) — hash claims verified.** bars.lua, tests/bars_state.lua,
  classes/paladin.lua, tests/paladin_state.lua, config.lua,
  tests/appearance_defaults_state.lua, power_bar.lua, weave_range.lua, hunter_ui.lua
  (md5 `d899ef5f76f70cf8a7a860068dc59fe4`), tests/power_bar_state.lua all match their
  lane reports. The only "byte-identical" claim that does **not** hold is the one in the
  superseded report (B2(d)). Mid-flight hashes in `bench/appearance_fix_2026-10-28.md:167-170`
  (tests/bars_state 995f286f…, bars.lua 42b9d9f6…) are snapshots of a file two later lanes
  rewrote — superseded by ranged-forced S8, not a false claim.
- **B5 (INFO) — shared-file pin sets intact.** `tests/bars_state.lua` carries
  §12a/12a-bis/12b (ranged-forced), §12c/12d (layout-finish), §12e (appearance-fix) at
  :3409-3900; neither lane clobbered the other. `main.lua` was written by three lanes plus
  a comment-only orchestrator pass; the comment pass survived (422-432 reads correctly).

## C. Silent-failure sweep

**C1. Remaining AceDB `'**'` plain reads used for a decision / passed to an API.**
The class-of-bug reads fixed this wave: `sound_channel` (widgets.lua:63-70, paladin
classes/paladin.lua:1164-1175), `get_class_table` (main.lua:247), `bar_full_delay`
(main.lua:1564), `gcd_marker_offset_mode` (option_table_presets.lua), plus the appearance
flag and the ranged latch (config.lua:177, bars.lua:524). Remaining:

- **C1a (LOW) — `main.lua:258 get_hand_table` still plain-reads `class[hand]`.** The class
  row carries the `'**'` metatable (config_presets `['**'] = bar_defaults`), so a read of
  a hand the class does not ship creates a defaults hand row on the profile. I could not
  find a reachable caller that passes an unshipped hand: `iter_hands()` is the hand
  authority, `power_bar.usable_hand_frame` (:184-195) reads the frame before calling
  `bar_is_enabled`, and `ensure_bar`/`bar_is_built` are hand-driven. Latent, and already
  filed by `latent-trap-hardening` as follow-up.
- **C1b (LOW) — options-table class reads are unguarded.** 194 direct
  `get_class_table().<field>` dereferences (`option_tables.lua:153…7418`; e.g. :153, :168,
  :236, :255, :311, :442, :802, :1686, :1908, :2145, :2740, :4369, :4725, :7226, :7418)
  plus `designmode.lua:737/739`. On the shipped ten class tokens these are defaults-backed
  and safe (see §P1-1); on a token outside `ST.defaults.profile` they now raise (§P1-2).
  They do not *create* rows for shipped classes.
- **C1c (INFO) — reads that remain but cannot create a table**: hand-table leaf reads
  (hand tables carry no metatable — config.lua:187-191 documents this and it is true of the
  vendored copy: `copyDefaults` only sets a metatable where a `'*'/'**'` key exists,
  Libs/AceDB-3.0/AceDB-3.0.lua:88-107), and class-row keys that `class_defaults` actually
  ships (`class_enabled` main.lua:300, `form_vis_*` :2457-2471 with the keys at
  config_presets.lua:443-449, `require_in_range` main.lua:2888, `dim_oor/dim_alpha`
  :2755/:2760). `main.lua:860 welcome_message` is a profile-root key that
  `ST.defaults.profile` ships (config.lua:24).

**C2. pcall / `st.guard.run` sites that can hide a permanently dead subsystem.**

- **C2a (MED) — guard quarantine goes quiet and `/st diag` does not name the site.**
  `st.guard` quarantines a throwing site after 25 failures (guard.lua:26-30, :120-160),
  announces it once in chat, then never calls it again. The counter can be read —
  but `/st diag` prints only the total: `bar_hook_errors=<count>`
  (main.lua:2974-2979, from `print_runtime_diag`, main.lua:2961-3055). `diag.lua` never
  reads `bar_hook_errors` at all. So a per-tick subsystem (hunter_ui's 11 guarded updaters,
  bars/ldb/rotation-text sites) can be dead for the session while the diag shows one number
  the user cannot attribute. Recommendation: print `by_site`/`quarantined` site names on
  the runtime line (cheap, bounded) — **not release-blocking, but this is the exact
  "diag said no errors while a bar was wrong" class the audit exists for.**
- **C2b (INFO) — the 5 s init deadline** disables a library that never reports and prints
  one notice (`flags deadline=fired`, diag.lua:354-372). By design
  (AGENTS.md), one-time, visible. Acceptable.
- **C2c (LOW) — migration pcalls swallow silently.** main.lua:435-438 and
  option_tables.lua:7731-7738 wrap both login-time rules in pcall with no counter and no
  notice. If either throws, login continues and the rule silently never applies (the
  appearance flag is retried next login; the ranged latch may already be written — see
  §E6). Add a counter (e.g. `migration_errors`) to the runtime diag line.
- **C2d (INFO) — remaining pcall sites are probe/read wrappers** with documented fallbacks:
  diag.lua (35 — every field in its own pcall; a broken field costs its line, diag.lua:549-620, :885-925),
  compat probes (documented per client), classes 6-11 (API/rank probes with fallbacks),
  widgets preview sound (widgets.lua:150-180), power_bar height (power_bar.lua:149-161),
  bars frame getters (bars.lua:219). These fail open, not mute.

**C3. `/st diag` surface** — see §P4 for the full answer: dead engine/hand, hidden bar,
stuck tint, activity window, power-bar orphaning.

**C4. Errors caught and only printed once.** guard.run's "first failure of a site" banner
(guard.lua:120-145) and every one-time notice (init deadline, migration, unknown-hand,
Retail stand-in). Recurrence stays observable only through the verbose in-memory error ring
(diag.lua `error_lines`, :822-845, newest-last) — **INFO**, provided the user runs
`/st diag` (not just `/st diag` at login). No change needed.

## D. Cross-client invariants

- **D1 (INFO)** — no bare cross-client API outside `compat.lua`. The only non-comment hits
  are `LibGlobalCooldown.lua`, which aliases `GetCombatRating/GetCombatRatingBonus/
  GetSpellCooldown/GetSpellInfo/GetShapeshiftForm` through `st.api` (:21-22, :53-56).
  `UnitDistance`/`CheckInteractDistance`/`C_Spell`/`C_Container`/`C_ClassTalents`/`GetTimePreciseSec`
  appear only in comments or compat. (`GetTime` remains inside the lib, which is its
  pre-existing clock; the aligned `st.api.get_time` is used by our code.)
- **D2 (INFO)** — 7 TOCs and interfaces: base `11509, 20506, 38002` (classic-line only,
  ships `LibClassicSwingTimerAPI`); Vanilla 11509 / TBC 20506 / Wrath 38002 (ship the lib);
  Mainline `120100, 120105, 16001` (omits the lib); Cata 40402 and Mists 50500 (omit the
  lib, inert by design). `tests/toc_check.lua` 1104/0.
- **D3 (INFO)** — version `2.1.3` in all 7 TOCs (`## Version: "2.1.3"`) and main.lua:5.
  No bump, as ordered.
- **D4 (INFO)** — no `TODO/FIXME/XXX` in product files; **zero** uncommented bare `print(`
  in product `*.lua`; debug output stays behind `st.debug` + `st.utils.print_msg`.
- **D5 (INFO)** — family gates intact: shaman weave and paladin guide are explicitly NOT
  gated on `is_mainline` (classes/shaman.lua:2619-2658, classes/paladin.lua:1908-2081
  comments + `st.is_retail` only where documented).

## E. New-wave regression hunt

- **E1 (MED) — the offhand Width widget is a lie.** `option_tables.lua:7203-7239` renders a
  per-hand Width range whose setter writes `offhand.bar_width` and reconfigures; but
  `bars.lua:292-311` (`hand_bar_size`) ALWAYS replaces the offhand width with the
  mainhand's when no override is passed (`:309-310`). So for every offhand-owning class
  (hunter/rogue/warrior/DK) the offhand Width slider moves a saved key that nothing reads.
  Height was fixed by layout-finish (locked + mirrors, option_tables.lua:7240-7312); Width
  was not. This is HU-38 D2 only half-closed. Fix by locking the offhand Width widget (or
  routing it to the mainhand key, as the Height widget does).
- **E2 (MED) — the activity gate is absolute; "Always" does not win.** main.lua:2876-2930:
  `hand_show_condition_met` returns true for `show_behaviour == "always"`, then :2924
  hides offhand/ranged anyway when `hand_is_in_use` is false. Matches HU-38 D1 (open
  operator ruling). Documented; not a code defect, but the options panel still offers
  "Always" without saying it cannot surface an idle hand.
- **E3 (MED) — hunter visual set is driven only by the ranged bar (HU-37).** The cast bar,
  range helper, Rapid Fire bar, cast zone, pet badges and aspect icon are created as
  CHILDREN of the ranged bar frame (hunter_ui.lua:272-278, :329-337, :339-365, :366-381,
  :382-397) and the whole set is updated only from `ui.on_bar_update` when
  `hand == "ranged"` (hunter_ui.lua:1649-1666 → `ui.update` :1606). `ranged_bar_ready`
  (:163-165) checks only the hand option/weapon, not the activity gate. A hidden frame runs
  no OnUpdate (asserted by the module's own comments, hunter_ui.lua:185-186,
  classes/hunter.lua:1284-1289; client semantics, not proved in this audit), so while the
  ranged bar is activity-hidden the hunter set cannot paint. **Exact conditions:** hunter,
  `has_weapon` true, ranged hand enabled, and (`auto_repeat_active ~= true`) and (no
  completed shot 75/3018/2764/5019 within `hand_activity_window`) — i.e. Auto Shot not
  armed and no shot in the last 1.5-8 s. Normal Auto Shot play keeps the bar up between
  shots because the armed flag is a receipt (main.lua:2841). The failure is a hunter
  casting Steady Shot / Volley / a channel with Auto Shot off: **no cast bar at all**, not
  a stale one. Needs the operator ruling (HU-37) or a always-visible driver in hunter_ui.
- **E4 (LOW) — the placement band reads SAVED melee geometry.** `bars.lua:418-455`
  (`melee_reserved_band` → `saved_row_extent`) uses the melee rows' saved y/point/scale.
  For hunters the rendered melee stack is re-pinned under the ranged bar at runtime
  (hunter_ui.lua:191-232), so a hunter whose saved MH/OH rows were dragged can get a
  ranged target away from its shipped row (still above the saved band, once, with the
  notice). Corresponds to ranged-forced V4 ("the hunter stack is unobserved").
- **E5 (LOW) — raising `melee_bar_height` live can overlap the ranged row** until the user
  drags it: the placement rule is one-shot by design (no per-option re-run; re-running
  would be geometry hopping). Documented residual V5; belongs in the docs.
- **E6 (LOW) — the ranged latch is written before the geometry is validated**
  (bars.lua:527 write, then :528-546 return "unknown" for an unreadable layout). A corrupt
  profile therefore latches "unknown" and is never retried — no move, no notice, forever.
  Prefer reading geometry first and latching only on `moved/kept/no-ranged`.
- **E7 (LOW latent) — the latch is written before the `has_hand("ranged")` check**
  (bars.lua:527 then :528). Every paladin/druid/shaman/DK login writes
  `ranged_placement_213 = 2` into its class row for nothing; if a class ever gains a ranged
  hand, the stale latch would make the rule a no-op for it. Move `has_hand` first.
- **E8 (INFO) — idempotence proven, both rules.** Ranged: second run returns "done" with a
  write-counting proxy at **0 field writes**, **0 prints**, and a later drag preserved
  (tests/bars_state.lua:3551-3560, :3664-3669); the first-pass `true` latch is upgraded
  exactly once (:3645-3672); fresh shipped rows are "kept" with 0 geometry writes
  (:3719-3722); non-ranged classes answer "no-ranged" (:3703). Appearance: second run 0
  (tests/appearance_defaults_state.lua:374-402), and a real vendored-AceDB **second login**
  over the same SavedVariables returns 0 with the raised alpha intact (:613-621). Verified
  by running both suites.
- **E9 (INFO) — no per-tick saved writes.** `onupdate_common` writes frame geometry and
  session state only (bars.lua:1103-1260); `hand_bar_size` is read-only from the tick path;
  the placement rule has exactly one call site (main.lua:437) and a static pin that no
  OnUpdate/callback can reach it (tests/bars_state.lua:3745-3765); power_bar compares the
  anchor rect before re-pointing (power_bar.lua:236-265, :275-303).
- **E10 (INFO) — power bar under the melee stack is never given up.** The offhand ROW owns
  the slot whenever the class can use an offhand, even while idle (power_bar.lua:206-232,
  `usable_hand_frame` :184-195 deliberately ignores visibility); height clamped 10-30
  (:149-161) and the reserved band uses the same clamped height + GAP (:137-147, :51-54).
  It hides only when no melee row frame is on screen at all (:206-216).
- **E11 (INFO) — hunter queue tint is cycle-gated as ordered.** Paint requires
  `hunter_mainhand_cycle_live` = in combat + MH not full + not engine-dead + live
  start/ends_at (classes/hunter.lua:163-176, used at :1434 before any colour write), clears
  on swing consume/target change/cycle loss with a same-path repaint
  (:1035-1057, :1246-1275). No `self.ranged` coupling (source pin).

## F. Release artefacts and trail integrity

- **F1 (INFO)** — lane reports present for all 8 lanes: hunter_tint, bars_decouple,
  layout_finish, appearance_fix, ranged_forced (with SUPERSEDING REPORT), widgets_guard,
  latent_trap_hardening, paladin_sound; desk journals and done signals present for each
  (ranged-forced has the superseded 05:01 signal + the authoritative 05:12 one;
  latent-trap-hardening has four signals — noisy but self-describing).
- **F2 (MED)** — the stale central entry described in §B3 must be voided; the earlier
  verdict in this same file must not be quoted.
- **F3 (INFO)** — `docs/` untouched (all mtimes ≤ 2026-09-02). `bench/` reports are
  dated/named. Briefs exist on disk for every lane.
- **F4 (INFO)** — hands-up coherence: HU-35/HU-36 RESOLVED by ruling (2026-10-28);
  HU-37/HU-38 OPEN; HU-29/HU-33 stay per their own notes. No contradictory row found.
- **F5 (INFO)** — attribution is now single-counted: the paladin `play_twist_sound` code fix
  is credited to latent-trap-hardening, the behavioural proof to paladin-sound
  (tests/paladin_state.lua §18, 38 checks). One defect, one row.

## G. In-client checklist (operator — TBC Anniversary 2.5.6 AND Classic Era 1.15.9)

No in-client proof exists for any of this wave. Copy the tree (skip tests/docs/bench/desks/
.git), `/reload`, and walk both clients:

1. Login with no Lua error popup; chat shows `Version 2.1.3 loaded!`; no migration notice on
   a profile that already logged in with this build (the latch is already written).
2. **Placement (the operator's own profile).** If it last logged in before this build:
   expect **one** line, "the ranged bar was moved above the melee bars (that row belongs to
   the power bar)…" or "…placed in the standard layout…"; the ranged row sits above the
   melee stack with the power bar directly under the offhand row. `/reload` → **no second
   notice, no second move**. Drag the ranged bar, `/reload` → it stays where you dragged it.
3. **Placement matrix:** warrior and rogue (ranged-owning melees) each move once; paladin/
   druid/shaman must NOT move anything and must not print.
4. **Activity gate:** warrior/rogue — fight in melee: the ranged bar stays hidden even in
   combat; fire Shoot/Throw → it appears for ~2 cycles and hides. Offhand: swing once →
   offhand bar appears; stop → hides after its window. Hunter — Auto Shot at range: ranged
   bar stays up across the cycle; turn Auto Shot off for >2 cycles → bar hides.
5. **Hunter visual set (HU-37 gap):** with Auto Shot OFF and no shot in the last window,
   cast Steady Shot — confirm whether a cast bar appears. It is expected NOT to (known gap);
   report what you see. Also confirm the queue tint only paints while the MH cycle is live
   and clears on swing/target swap/combat exit.
6. **Pair height + the offhand Width lie (E1):** set "Melee pair height" → MH and OH resize;
   "Use each hand's own height" clears it. Open Offhand → Width: move it — does the offhand
   bar change? (Expected: **no**; that is the E1 defect, fix or lock it before shipping.)
7. **Power bar:** under the offhand row (dual-wield classes) / mainhand row (single-melee);
   set height 10 and 30 and confirm the bar follows and the ranged row does not collide;
   hide/show the melee bars and confirm the power bar hides with them, never floats orphaned.
8. **Era crash fix (B1):** on Classic Era, get a combat-rating update (equip/change gear,
   enter combat) — no `GetCombatRating(ratingIndex)` error in chat or the error log; /st diag
   shows no error ring entries.
9. **`/st diag` verbose:** per-hand `bar state <hand> built=… shown=… alpha=… tick=… start=…
   speed=… ends_at=… now=… progress=… full=… paused=… dead=… vf_width=… fill=… pos=x,y` and
   the hunter `queue=` flags on the mainhand line; the runtime line
   `swing_mainhand=…/…/…`, `swing_offhand=…`, `swing_ranged=…`, `swing_last=…`, plus
   `engine=` and `dead=no`. Confirm `tick=yes` and `fill` > 1 while a bar is swinging.
10. **Docs claims:** after the docs pass, confirm the release notes match what you actually
    saw (see §P5-3 for the exact allowed/forbidden claims).
11. **Sound hardening:** Options → sound preview plays with the "Master" fallback on each
    client; a paladin twist cue fires at least once with a saved channel string.

---

## P1. `ST:get_class_table` → `rawget(profile, self.player_class)`: every caller, and the verdict

Implementation: main.lua:233-248 (`rawget` at :247; nil answer documented at :234-239).

**P1-1 (INFO) — no shipped class changes behaviour, first login included.** `AceDB:New` is
called with `true` (…Default profile) and `db.profile` is lazily materialised on first
access; that path ALWAYS runs `copyDefaults(profile, defaults.profile)`
(Libs/AceDB-3.0/AceDB-3.0.lua:187-196, :88-127), which raw-sets a real table for every one
of the ten class tokens `ST.defaults.profile` lists (config.lua:65-74). The first
profile access in `OnInitialize` is `get_profile_table` at :435 (which runs
`copyDefaults`); the migration's class-row read follows at :437 — so the row is present
on the very first login. Pinned by
tests/main_init_state.lua:2323-2342 (NILSWEEP N1 / LATENT L2) and :2495-2502.

**P1-2 (MED) — the only behaviour change is a class token outside the ten.** For
`MONK`/`DEMONHUNTER`/`EVOKER` (Retail only; the other seven tokens are vanilla-family
classes that never occur on the classic line) the old plain read returned a
metatable-created `class_defaults` table; `rawget` now returns nil. main.lua handles nil
everywhere (N1-N7, :285-317, :786-810, :1026-1034, :2444-2471, :2931-2950), and
bars/hud/power_bar/weave_range/ldb/designmode-enter all guard (`designmode.lua:1130-1147`
refuses loudly with no class row). **What does not guard:** the options surface —
194 direct `get_class_table().<field>` derefs in `option_tables.lua` (see C1b; the first hit
at :139-145 / :153 will be the one that raises) and `designmode.lua:737/739`. So on Retail,
a Monk/DH/Evoker opening `/st` now gets a Lua error where it used to get a defaults panel
(and silently wrote a junk class row — itself a latent bug). Not reachable on any
classic-line class, no bar/engine path affected; recommend a nil-guard or a read-only
defaults fallback **before Retail is advertised**, not as a classic-line blocker.

**P1-3 (LOW)** — `get_hand_table` still plain-reads the hand (main.lua:258).
**P1-4 (INFO)** — pre-AceDB callers now get nil instead of the old "index a nil value"
error (strictly safer; comment at :236-239 is accurate).

## P2. The activity gate: can a hand be permanently hidden?

**P2-1 (INFO)** — only offhand and ranged are gated (main.lua:2794-2797); mainhand is never
gated. No class has ranged-only swing sources (`ST.class_hands`, main.lua:98-108: every
ranged owner also owns mainhand), so the gate can never leave a player with zero bars — a
ranged-only hunter still has the MH bar, subject only to the hand's own show condition.

**P2-2 (INFO) — exact "in use" conditions.**
- Offhand: a player-sourced `SWING_DAMAGE`/`SWING_MISSED` with the offhand slot
  (main.lua:1136-1150, isOffHand = return 21 / return 13, verified against the vendored
  lib's own parse, Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:395-407) on
  classic-line clients; on Forever, its `PLAYER_SWING` START (main.lua:1505-1511).
- Ranged: `UNIT_SPELLCAST_SUCCEEDED` with 75/3018/2764/5019 (main.lua:2010-2016,
  :2188-2192) or `auto_repeat_active == true` (main.lua:2841).
- Window: 2 × the hand's speed, clamped to [1.5 s, 8 s] (main.lua:2785-2832).

**P2-3 (MED) — permanent-hide conditions, stated exactly.**
- By config/weapon (intended and permanent): `enabled=false`, or `has_weapon=false`
  (no offhand weapon / no ranged weapon) — main.lua:2858-2870, main.lua:961-986.
- By the gate (permanent only for a play pattern that never produces a receipt): offhand
  hidden forever if the client path never delivers a swing receipt (Retail: no classic
  CLEU and no Forever engine, but Retail has no swings at all, so the whole addon is inert;
  no shipped classic-line client is in this state); ranged hidden for any character that
  never completes a shot and never arms Auto Shot (wand casters who only cast spells — the
  intended "only when used" behaviour).
- **The hunter-specific chain (HU-37):** while the ranged bar is hidden, the entire hunter
  visual set is frozen/invisible because it is parented to that frame and driven only by
  its OnUpdate (E3). The ranged bar is hidden exactly when `auto_repeat_active ~= true`
  and no shot receipt is inside the window; so a hunter casting Steady Shot with Auto Shot
  off gets no cast bar ever. Nothing recovers it except a shot (or toggling Auto Shot on).
- **UNVERIFIED (client):** that hidden frames run no OnUpdate. Stated by this repo's own
  code comments and standard client semantics, but not observed by this audit — §G step 5
  closes it.

**P2-4 (LOW)** — on the classic line there is no engine-side ranged receipt (the lib's
ranged START is deliberately excluded, main.lua:1505-1508); the ranged bar therefore
depends on `UNIT_SPELLCAST_SUCCEEDED`/Auto-Shot for its receipt. No evidence of suppression;
noted because an addon that swallows cast events would strand the ranged bar.
**P2-5 (INFO)** — mounted hunters read auto-repeat false (classes/hunter.lua:971-981), so
after the window the ranged bar hides while mounted; correct (no shooting while mounted) and
the class UI hides with it.

## P3. Idempotence, notice discipline, login safety

**P3-1 (INFO) — ranged placement, run twice:** second run returns `"done"`, the counting
proxy records **0 field writes**, **0 prints**, and a later drag is untouched
(tests/bars_state.lua:3551-3560, :3664-3669). First-pass `true` latch upgrades once
(:3645-3672). Fresh profile: `"kept"`, 0 geometry writes — but the latch write DOES happen
and is pinned (:3719-3722).
**P3-2 (INFO) — appearance migration, run twice:** second run 0; real-AceDB second login 0;
a polluted profile (table at the flag) migrates once and latches
(tests/appearance_defaults_state.lua:374-402, :554-565, :613-621; bars_state §12e
:3725-3760). Verified by executing both suites this pass.
**P3-3 (INFO) — notice at most once, and login-safe.** The notice is inside the latched
branch only (bars.lua:524-527 early-return `"done"`), the rule has exactly one call site
(main.lua:433-439), and that call is pcall'd — a bad profile or a broken chat frame cannot
abort login; the chat call itself is pcall'd too (bars.lua:574-581). Because the latch is
per class row per version, "once per class per session" is satisfied (stronger: once per
profile per version).
**P3-4 (LOW)** — the notice text ends "your position is never changed again"
(bars.lua:568-573). True only until a future `RANGED_PLACEMENT_VERSION` bump; say "this
update" or make the sentence version-aware.
**P3-5 (LOW/INFO)** — "fresh profiles 0 writes" (lane report S3, journal) is precise for
geometry only: the latch field is written on the first login of every profile and every
class, including non-ranged classes (§E7). Not a defect; the release note must not promise
"no writes".
**P3-6 (LOW)** — if the latch write succeeds and the geometry read then throws (pcall
swallowed, §C2c), the row is stranded with the version latch. Rare (all reads are pure
profile reads after the row exists) but the failure is silent; see §E6 for the sibling case.

## P4. Does `/st diag` surface the six named failure modes?

Login line (always): family/iface/version/engine/lrc/lcd/ldb + per-guide state
(diag.lua:339-352). `/st diag` adds flags, modules, ticks, secrets, per-hand BAR STATE,
ids, error ring (diag.lua:885-925) plus main.lua's runtime line (main.lua:2961-3055).

| Failure mode | Surfaced? | Evidence |
|---|---|---|
| Dead engine | **Partly** — `engine=<token>` on the login line; `swing_<hand>=start/update/stop` + `swing_last=<kind>:<hand>:<age>s` on the runtime line. A shape-inert engine also sets `dead=yes` per hand. "Engine nominally live but silent" is only visible by reading the zero counters. | main.lua:2961-3055; bars.lua:1117-1127 |
| Dead hand | **Yes** — `built=no`, `tick=no`, `dead=yes`, `progress`, `fill` width. | diag.lua:549-600 |
| Hidden-but-expected bar | **Partly** — `shown=no` is shown, but the line does not say WHY (activity gate vs. show_condition vs. enabled=false vs. no weapon vs. unbuilt). | diag.lua:549-600; main.lua:2876-2930 |
| Stuck queue tint | **Yes (state)** — `queue=raptor:<yes/no>,steady:<yes/no>` on the mainhand line; no "expected" reference, so "stuck" is a judgement. | diag.lua:532-545, :583-600 |
| Activity gate stuck closed | **NO** — no `has_activity`, `last_activity_at`, `auto_repeat_active`, computed `in_use`, or window field. | main.lua:2799-2853 not read by diag.lua |
| Power bar orphaned | **NO** — no power-bar line at all (not in diag.lua; `power` appears only in the secrets probe list at :630). Cannot distinguish off / no anchor / no power API / anchored to a hidden row. | diag.lua (no reader); power_bar.lua:367-408 |

- **P4-1 (MED)** — add (a) three activity fields to each gated hand's BAR STATE line, (b) a
  one-line power-bar state, (c) a `why=` reason token for `shown=no`. This is the remaining
  gap the operator's 2026-10-28 complaint ("it said there was no errors, meaning something
  was missed/silent") was about.
- **P4-2 (LOW)** — `bar_hook_errors` is a bare total; quarantine site names are not printed
  (§C2a).

## P5. Version discipline, prints, and what the docs must claim

**P5-1 (INFO)** — 2.1.3 in all 7 TOCs + main.lua:5; no bump; base interface list is
classic-line only; Mainline/Cata/Mists omit the swing lib (D2). `git status` shows no new
version header anywhere.
**P5-2 (INFO)** — no debug prints (`0` uncommented bare `print(`), no TODO/FIXME introduced.
**P5-3 (MED) — docs are NOT updated for this wave, and one existing sentence is now wrong.**
CHANGELOG.md / README.md mtimes are 2026-10-27 06:57; the 2.1.3 section does not mention the
activity gate, the forced ranged placement, the melee pair height, the hunter queue-tint
cycle gate, the `/st diag` BAR STATE line, the Era `CR_HASTE_SPELL` crash fix, or the sound
hardening — **and** its power-bar sentence ("under the bottom-most visible melee swing bar
(offhand when used, else mainhand)", CHANGELOG.md:33-36) is contradicted by
power_bar.lua:206-232 (the offhand ROW owns the slot even while idle).

**What the release notes MUST claim (2.1.3, no bump):**
1. Offhand and ranged bars are activity-driven: they appear only after a real offhand swing
   or a real shot (Auto Shot / Shoot / Throw / Shoot Wand), or while Auto Shot is armed;
   combat state alone no longer shows them; window = ~2 cycles, clamped 1.5-8 s.
2. The ranged row is normalised ONCE to the standard layout above the melee stack on the
   first login after the update, for every class that owns a ranged hand, including a
   dragged or scaled saved row; one chat notice; later drags are respected; the row under
   the melee stack is reserved for the power bar.
3. One "Melee pair height" sizes mainhand and offhand together; clearing it returns each
   hand to its own saved height; the offhand always renders at the mainhand's width AND
   height; the offhand Height slider is locked and mirrors the mainhand.
4. The hunter melee stack is unchanged, and the Raptor/Steady queue tint now paints only
   while a live main-hand melee cycle exists, clearing on swing consume, combat exit and
   target change.
5. The power bar sits in the slot under the melee stack: it anchors to the offhand ROW
   whenever the class uses an offhand (even while that hand is idle), else the mainhand
   row; it hides when no melee bar is on screen; height 10-30 px.
6. `/st diag` verbose gains per-hand BAR STATE lines (built/shown/alpha/tick/cycle
   fields/full/paused/dead/fill/pos and the hunter queue flags) — diagnose a silent bar
   without an error.
7. Sound settings can never error the client (channel must be a string, "Master" fallback,
   playback pcall-contained) on the paladin twist cue and the options preview.
8. Correctness: Classic Era COMBAT_RATING_UPDATE no longer raises (`CR_HASTE_SPELL` nil on
   vanilla; literal 20 + pcall); class-table/settings reads no longer materialise AceDB
   default tables.

**What the release notes MUST NOT claim:**
- Any in-client verification (there is none yet).
- That a dragged ranged row survives the first login after the update (it is moved once;
  only post-update drags are kept).
- That "Show: Always" overrides the activity gate (HU-38 open).
- That the hunter cast bar / range helper / Rapid Fire bar / badges work while the ranged
  bar is hidden (HU-37 open — see §P2-3).
- That the offhand Width slider changes the offhand bar (§E1; fix or lock it first).
- That the power bar follows the bottom-most *visible* melee bar (it follows the offhand
  row when the class can use an offhand).
- That the vendored swing library's ranged/parry/extra-attack behaviour is fixed (HU-29
  open, library stock) or that the range helper uses protected range checks (HU-23: exact
  yards only).
- That Cataclysm/Mists are supported clients, or that the version was bumped.

---

## Manifest — audited tree (mtime local; sha256), snapshot 2026-10-28T09:48:37Z

| file | mtime | sha256 |
|---|---|---|
| main.lua | 2026-10-28 05:16:38 | 4c8573f2debc00826292f6ba57dcacf1518395c79079f905d0b7688a4e9c9e2e |
| bars.lua | 2026-10-28 05:01:34 | 30c107ffe3742a07e3a06d6298a8999dbee482be1637eb2366e7482c0e631585 |
| config.lua | 2026-10-28 04:51:58 | b21af49e00fbc5b8e96d89d3059f6d269b83b5660d94eceee57c2bccb1d65433 |
| config_presets.lua | 2026-10-28 05:14:19 | 2bd1e5b69e7481f5e199aadb5a04a4b243880bcedcc622aeb80c916a0691a748 |
| widgets.lua | 2026-10-28 05:09:41 | 0066bc9ca8be4272b0e23e1c6bca4372df9234dd3f17bc471c3b3715c84a78ff |
| diag.lua | 2026-10-28 04:14:21 | 07bd21fb4a02c368f175cc9c8e997eb71e3ea0b6d495b33d79fd6752eafea301 |
| power_bar.lua | 2026-10-28 03:18:13 | 42dcce370b8c7904ff8e7070d8f69687c7a1f1eb32919f8703971513cfdff0b7 |
| option_table_presets.lua | 2026-10-28 05:16:07 | c6059e38a306e08b5c6b538eef6eac4fa1a8b9b61ea1f9836b835c9c2c560dfe |
| option_tables.lua | 2026-10-28 04:17:43 | 8b55e48dcb2a57b9491334ce29054399cbffbeee0176cefd42130b67123f50ff |
| hunter_ui.lua | 2026-10-27 06:56:33 | 7a0fca5d61bcde8bd670412a79a1b3db710794b206c6677769951381116da67a |
| weave_range.lua | 2026-10-25 13:15:16 | 480b70e86476b9c9746d2149c306a21707b0cb2367f98ac308bebd4d83a83505 |
| LibGlobalCooldown.lua | 2026-10-28 02:49:05 | 77818d57e78c68afc07bff98475b7cb463831ba92a91a5c7c093fed17e75fe38 |
| classes/hunter.lua | 2026-10-28 03:20:47 | 8bf7299a58df43ec078db254774f25b46f185d7e3156ff4ec48af20f9b40c27a |
| classes/paladin.lua | 2026-10-28 05:21:07 | 81b7d4cfdcf98fc93ed491cdfba576b3ecc26ce02c1b0a81aaee27791143b882 |
| tests/bars_state.lua | 2026-10-28 05:07:06 | 354944237588147a5758299dad29a26b5e0eab3884ad110239326e0533663e41 |
| tests/appearance_defaults_state.lua | 2026-10-28 04:55:32 | b257bdcc9e2da167db0faea30c78a0553d3ff3b14ac93a3fb545686f72f601d4 |
| tests/rotationtext_state.lua | 2026-10-28 05:08:12 | d9de8da31e0c9c79cb342d9945c33d11b4e51b093d9fec7bb3046780b8e2590d |
| tests/paladin_state.lua | 2026-10-28 05:21:08 | fcc0fb66d5ed1ce7e898c4bf9c8c55d1f3079ef27910651f8797beb61364b92f |
| tests/power_bar_state.lua | 2026-10-28 03:26:58 | 23f736bf656125e54f435b268ade61824cf5dfcb7445843342516b08bd2e3732 |
| tests/main_init_state.lua | 2026-10-28 05:18:13 | bdade2a11a5613dff3c0073fae6217ea915d7a72c4a70276e788b6521ddc89ae |
| tests/options_load_state.lua | 2026-10-28 05:18:23 | 37c8c461d2b784a93f791977c581322c0ab428ea212891ca18ee35fc53c7626b |
| tests/diag_state.lua | 2026-10-28 04:26:29 | ba55c0f78ea7fe21d189f6dd62d051c71c1dae6d0fc3cb91dd66d9c0992c2edc |
| SwedgeTimer.toc | 2026-10-27 06:44:55 | 38b94f2118e6f5aae7c60029532eb66c6bd993572b62ca4af729e858939ac429 |
| SwedgeTimer_Vanilla.toc | 2026-10-27 06:45:01 | 94dcd465875f575ed6fd0066ac88d21e0e05a9b889c5ef56140747c694a9ae18 |
| SwedgeTimer_TBC.toc | 2026-10-27 06:45:01 | 2106e6c248eeda44705ea6cdaa3a41bfa8f32fe078e5a3a2f0879b9adecd4b19 |
| SwedgeTimer_Wrath.toc | 2026-10-27 06:45:01 | ff13a6a35203c3b810ea00e7d9e3e80a6cd1286437d0c3a28d877d0d90f930ff |
| SwedgeTimer_Mainline.toc | 2026-10-27 06:45:01 | a5516e1c7e5e0f4e1bcf143f9f93ac772a199f644416fdeb3da602f3debe523b |
| SwedgeTimer_Cata.toc | 2026-10-27 06:45:01 | 234dedf754ee5099420e4bbd3674d8c9295023fb54bdfbd366f35b4fa1958eb9 |
| SwedgeTimer_Mists.toc | 2026-10-27 06:45:01 | c97b76543f607958d7636c511aefe4d2c7b89926d7b2a2548869f262b90a3594 |
| CHANGELOG.md | 2026-10-27 06:57:23 | f0ee54272eb87672238b64154643ee1fb9ae6d9af0b5ecc059e847702194aa4f |
| README.md | 2026-10-27 06:57:29 | abb64897b91a69a99721d34a8e08fcdd760ad49003c9f74df3c77bc55484c699 |

Drift: baseline 09:30:01Z vs final 09:48:37Z — all hashes identical. No file changed under
the audit. Tree quiet since 05:21:08 local.

---

## Severity summary

| id | sev | finding |
|---|---|---|
| E1 | MED | offhand Width slider is inert (writes a key `hand_bar_size` always overrides) |
| P1-2 | MED | Retail-only settings panel now raises for a class token outside the ten defaults |
| E3 / P2-3 | MED | hunter visual set (cast bar etc.) never paints while the ranged bar is activity-hidden (HU-37) |
| C2a / P4-1 | MED | quarantined subsystems and the activity/power-bar state are invisible to `/st diag` |
| E2 | MED | "Always" does not override the activity gate (HU-38 D1, operator ruling owed) |
| P5-3 | MED | release notes unwritten and one power-bar sentence is now wrong |
| B2 / B3 | MED | stale "publish-audit DONE" report + ledger block must be voided |
| E6 / E7 | LOW | latch written before validation / before the hand check |
| E4 / E5 | LOW | placement band uses saved hunter geometry; live pair-height change can overlap |
| P3-4 | LOW | "never changed again" notice overclaim |
| C1a / C1b | LOW | remaining `'**'` read patterns (hand getter; options getters) |
| C2c | LOW | migration pcalls swallow silently |
| B1 | LOW | LibGlobalCooldown edited outside every lane (correct fix, unproven in client) |
| P2-4 / P2-5 | LOW | ranged receipt depends on cast events; mounted hunter hides the ranged bar |
| everything else | INFO | verified as described above |

**No BLOCKER was found in the six supported classes' code paths** — the engine gate, both
migrations, the power bar, the hunter tint, the sound guards and the ten shipped class rows
all behave as their pins claim. The release is nevertheless not publishable as it stands.

## Verdict

Blocking list: **(1)** the offhand Width slider is a user-visible lie and must be locked off
like the Height slider (or routed to the mainhand key) — E1; **(2)** CHANGELOG/README must
be written for this wave and the stale power-bar sentence corrected — P5-3; **(3)** the
operator's in-client pass on TBC Anniversary + Classic Era has not happened, so nothing
here is in-client proof — §G; **(4)** HU-37 and HU-38 are open operator rulings that the
release notes must not paper over — E2/E3; **(5)** the stale "publish-audit DONE" report and
journal block must be voided so the trail does not claim a verdict from a tree that no
longer exists — B2/B3. Conditional extra: if Retail is advertised as supported, guard the
options surface for the three class tokens outside the defaults first — P1-2.

**NOT READY** (no code BLOCKER in the six supported classes; held by E1 + missing release notes + open HU-37/HU-38 rulings + the absent in-client pass)
