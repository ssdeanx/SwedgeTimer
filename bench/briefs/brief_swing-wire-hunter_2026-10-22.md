# Brief: swing-wire-hunter — why no swing bar moves (mh/oh/ranged, every class)

Date: 2026-10-22. Operator finding: **no swing bar works — ranged, mainhand,
offhand dead for EVERY class**. Last session's two fixes (dispatcher strip in
`main.lua`, options comparator) are offline-proven only (46/0, luacheck 2/0)
and the suites STUB the engine — the wire defect survived them. HU-25 open:
real-lib harness or in-client first. This lane is the read-only defect hunt
that precedes both. HU-27 (range-engine-tbc unreconciled) and HU-28 (registry
v7 vs bundled v8) are context, not scope — note interactions, do not resolve.

## Seat + mode

- Seat: `hunter`. **READ-ONLY**: no product-code edits, no file writes, no
  `run.sh`, no git. Return the report as your reply text; the orchestrator
  files it to the bench + desk journal + done signal.
- Skills first (operator order): call `skills_list`, then `skill_view` the
  lane skills you need (`hermes-agent` for orchestration context is NOT
  required on this desk — load the workshop lane skills:
  `bench-read`, `desk-open`, `desk-journal`, `signal-write`). Then follow
  them: journals before artifacts (`desks/journal.md` lane table, your desk
  journal if present, `bench/lessons.md`), then the bench artifacts below.
  If a skill is missing from your catalog, say which and proceed by the
  workshop map (`workshop.md`) + `CAIRN.md` + `AGENTS.md` conventions.
- Tool rule for `/home/sam/wow-ui-source`: `read`/`grep` are blocked there
  (`permission.rejected: external_directory`). Use `ast_grep_search` with
  `paths: ["/home/sam/wow-ui-source/Interface", ...]` and `lang: "lua"`.
  It sees the CHECKED-OUT branch (`classic_era`, 1.15.9) only — every
  branch-specific claim carries its branch; anything you cannot check on
  another branch is UNVERIFIED with the exact close-out (branch + file +
  line/symbol). Never paper a gap with a plausible answer.
- Standing rules: no git. New user-visible toggles nil-safe (not in scope —
  do not propose toggles without an explicit ask).

## Verified inputs (all exist on disk 2026-10-22, cite file:line)

SwedgeTimer side:
- `main.lua:12` (`LibStub("LibClassicSwingTimerAPI", true)` + flavor note),
  `main.lua:20-46` (make_swing_stub, STL pick: vendored-lib /
  forever-source / inert-standin, `ST.swing_engine`),
  `main.lua:75-76` (`SwingTimerInfo` closure over STL),
  `main.lua:316-423` (`OnInitialize`: `init_libs` once-gate,
  `SWING_TIMER_INFO_INITIALIZED` re-entry, 5s init deadline → inert-standin
  + one-time notice),
  `main.lua:682-776` (`init_libs` → `init_timers`, six
  `STL.RegisterCallback(self, "SWING_TIMER_*", ...)`),
  `main.lua:735-` (`init_timers`: `SwingTimerInfo(hand)` seed per hand,
  `engine_dead` when the stub returns nil-shape),
  `main.lua:918-962` (`ST.callback_event_handler`: the dispatcher strip —
  drops a leading `"player"`/`"target"` on `SWING_TIMER_*` only),
  `main.lua:1042-1190` (`note_swing_wire`, `ST:SWING_TIMER_{CLIPPED,DELTA,
  PAUSED,START,STOP,UPDATE}` handlers take speed-first:
  `(_, speed, expiration_time, hand)` / `(_, hand)`),
  `main.lua:600`, `main.lua:2078`, `main.lua:2138-2140` (CLEU registration
  points, diag `swing_source.diagnostic_text` hook).
- `bars.lua:58-60` (`ST.mainhand/offhand/ranged`), `bars.lua:713-722`
  (per-hand `onupdate`), `bars.lua:731-948` (`onupdate_common`,
  `engine_dead`/full/pause states).
- `compat.lua:39-127` (family detect: `WOW_PROJECT_ID` incl.
  `WOW_PROJECT_CAMELOT=18` → `FOREVER`; interface fallback `>=16000`;
  `st.is_mainline` = RETAIL or FOREVER), `compat.lua:1257`
  (`st.cleu_supported`, false on mainline), `compat.lua:1410+`
  (per-family spell wrappers).
- `swing_source.lua` full file (FOREVER-only engine: `available` =
  `family==FOREVER and IsEventValid("PLAYER_SWING")`; `on_player_swing`
  fires `SWING_TIMER_START(speed, expiration, hand)` speed-first;
  `STOP` hand-only; `UNIT_ATTACK_SPEED` 3-return rescale;
  `PLAYER_IN_COMBAT_CHANGED` clears cycles; `SwingTimerInfo` mirrors the
  lib contract).
- `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:41-47`
  (version flags: `isClassic/isBCC/isWrath/isCata/isMists/isRetail`),
  `:109-205` (`UNIT_SWING_TIMER_*` fires, all unit-id-led),
  `:264-274` (`SwingTimerInfo`), `:817-825` (legacy re-fire:
  `Fire(legacyEvent, ...)` keeping the unit-id lead),
  `:832-845` (self-registration of both `UNIT_` and `SWING_` sets),
  `:850-1502` (per-version spell tables; EMPTY when no branch matches).
- TOCs: `SwedgeTimer.toc:15,18,24` + `SwedgeTimer_TBC.toc` /
  `SwedgeTimer_Vanilla.toc` / `SwedgeTimer_Wrath.toc` (ship CallbackHandler
  v7 + the lib + `swing_source.lua`); `SwedgeTimer_Mainline.toc:15,23-24`
  (ships CallbackHandler v7 + `swing_source.lua`, NO lib); check
  `SwedgeTimer_Cata.toc` / `SwedgeTimer_Mists.toc` in-tree for what they
  ship. Bundled v8: `Libs/LibClassicSwingTimerAPI/Libs/CallbackHandler-1.0/`.
- `bench/swing_wire_status_2026-10-21.md` (honest state: what landed,
  what is UNPROVEN, what is unreconciled), `tests/main_init_state.lua §14b`
  (stubbed-engine wire pins), `desks/journal.md` (lane ledger, incl.
  2026-10-21 direct-fix + session-close entries), `hands-up.md` HU-25/27/28.

Reference side (fully functioning per operator — mine it, do not copy blindly):
- `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer.toc`
  (`## Interface: 11509, 20506` — Era + TBC only, no Retail/Forever path).
- `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer.lua`
  (`RegisterEvents`: CLEU + `UNIT_ATTACK_SPEED` + `UNIT_SPELLCAST_*` +
  `START/STOP_AUTOREPEAT_SPELL` + `UNIT_RANGEDDAMAGE` +
  `SPELL_UPDATE_COOLDOWN` + movement events; `OnEvent` → `HandleCLEU`).
- `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_State.lua`
  (`ns.HandleCLEU` ~`:1272`: `SWING_DAMAGE/MISSED` slot via off-hand flag,
  `SPELL_CAST_SUCCESS` AutoShot via `IsAutoShotSpell`, `SPELL_EXTRA_ATTACKS`,
  `SPELL_DAMAGE/MISSED` queued-melee + `RESET_RANGED_SWING_SPELLS`,
  `SPELL_AURA_APPLIED` druid forms; `StartSwing(slot,_,startTime)`,
  `StartRangedSwing`, `ResetTimer`, `SyncRangedTimerSpeed`:
  `UnitRangedDamage` / `GetSpellCooldown(75)` / haste fallback chain —
  incl. the TBC 2.5.5 `UnitRangedDamage`-returns-min-damage comment).
  It uses NO swing library — direct CLEU is the whole engine.

Blizzard reference: `/home/sam/wow-ui-source` branches
`classic_era`, `classic_anniversary`, `classic_titan`, `live`,
`origin/forever`. Orchestrator-verified Forever facts you may reuse without
re-proving (still cite branch+file): `SwingTimerDocumentation.lua`
(`PLAYER_SWING(swingDuration, swingType)`, `PlayerSwingType`
MainHand=0/OffHand=1/Ranged=2); `Blizzard_SwingTimer.lua`
(`ResetSwingTimer` sets `swingEndTime = GetTime()+duration` on
`PLAYER_SWING`, reads all three `UnitAttackSpeed` returns).

## Questions (answer each with file:line + verdict WIRED / BROKEN / UNVERIFIED)

1. Wire shape end-to-end: the lib's legacy `Fire(legacyEvent, ...)` keeps
   the unit-id lead (`"player", speed, expiration, hand`); the dispatcher
   strips one leading `"player"`/`"target"`; handlers take speed-first.
   Is the strip correct for EVERY `SWING_TIMER_*` event on EVERY hand
   (incl. hand-only `STOP`, `DELTA`, `PAUSED`, `CLIPPED`,
   `INFO_INITIALIZED`)? Does CallbackHandler v7 (shipped) vs v8 (bundled,
   unshipped) change the fired args? Is anything else registered on the
   `UNIT_SWING_TIMER_*` names that bypasses the strip?
2. Version detection vs Anniversary: `isBCC` requires
   `WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC AND
   LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE`. What does
   TBC Anniversary 2.5.6 actually report (project id? expansion level? is
   `LE_EXPANSION_BURNING_CRUSADE` even defined there)? If no table branch
   matches, which tables stay empty and what breaks: ranged drivers only,
   or melee too? Trace the Era-vs-Anniversary ranged drivers
   (`SPELL_CAST_START` / `FAILED_QUIET` isClassic-only vs
   `SUCCEEDED(75)` + `START_AUTOREPEAT`) and say exactly which hand dies
   where.
3. Registration + init gating: `init_libs` registers only the six
   `SWING_TIMER_*` names; the lib fires both `UNIT_` and `SWING_` sets.
   Is six enough on every family? Does `SWING_TIMER_INFO_INITIALIZED`
   fire on Anniversary at all (player/target units created? `UnitExists`
   gating?); if not, does the 5s deadline rescue or strand init, and what
   do the bars render (`engine_dead` vs frozen seed)?
4. TOC shipping: which flavor ships what (lib? which CallbackHandler?
   `swing_source.lua` on all flavors?). Consequences: Cata/Mists ship the
   lib with known-nil-table indexing defects (AGENTS.md gotcha) — in scope
   only as a note. Mainline ships no lib: Retail = inert stand-in (bars
   expected dead — confirm), Forever = `swing_source` (gated on
   `IsEventValid("PLAYER_SWING")`).
5. Forever path vs Blizzard's own: does `swing_source`'s payload order,
   hand mapping, `UNIT_ATTACK_SPEED` rescale, combat-exit clear, and
   `SwingTimerInfo` contract match `Blizzard_SwingTimer.lua` on
   `origin/forever`? Any missed Forever event
   (`WEAPON_SLOT_CHANGED`, `PLAYER_SWING_RANGE_UPDATE`,
   `UNIT_ATTACK_SPEED` unit filter)?
6. What SuperSwingTimer does that SwedgeTimer does not: enumerate the
   direct-CLEU inputs SwedgeTimer delegates to the lib
   (off-hand flag position per sub-event, AutoShot id source,
   extra-attack suppression, parry-haste, queued-melee spells,
   `START/STOP_AUTOREPEAT_SPELL`, `UNIT_RANGEDDAMAGE`,
   `SPELL_UPDATE_COOLDOWN`, movement pinning, `UnitRangedDamage` /
   cooldown / haste fallbacks). For each: does the vendored lib cover it
   on Era AND on Anniversary, or is it a real gap?
7. Retail: with the inert stand-in (`SwingTimerInfo` → nil-shape,
   `RegisterCallback` no-op) the bars are expected dead by design —
   confirm the user-visible state (one-time notice? `engine_dead` bars?)
   so a Retail "dead bars" report is not misfiled as this bug.

## Deliverable (reply text; orchestrator files it)

- Ranked defect list D1..Dn: each with symptom (which hands/classes/
  clients), root cause (file:line chain), verdict BROKEN or DEGRADED, and
  the minimal fix direction (no code — words only).
- UNVERIFIED list U1..Un: each with what could not be checked, what was
  tried, and the exact evidence that closes it (branch + file + symbol,
  or the in-client observation with class/client/steps).
- Explicit non-findings: wire shapes you checked and hold (with pins).
- Residuals outside scope (one line each, no chasing).
