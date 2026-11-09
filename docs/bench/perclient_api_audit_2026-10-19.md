# Per-client API audit — tests vs reference truth (2026-10-19)

**Objective:** verify our tests pass FOR EACH CLIENT by auditing per-client API truth vs test pins.
**Method:** read-only. `git -C /home/sam/wow-ui-source show <branch>:<path>` throughout; the
checked-out branch (`classic_era`) was never changed. No addon/test/bench edits, no checkout/commit.
**Branches mapped:** `classic_era` = Era/SoD 1.15.9 · `classic_anniversary` = TBC Anniversary 2.5.6 ·
`classic_titan` = Wrath Titanforge 3.80.2 · `origin/forever` = WoW Forever 1.60.1 ·
`live` = Retail 12.1.x. No Cata/Mists branch exists in the reference.

## 0. Harness verdict: RED (38 steps, 3 failed) — tests do NOT all pass on this tree

Observed 2026-10-19 via `bash tests/run.sh` (two consecutive runs, same 3 failures):

- `tests/guide_contract.lua` — 5 of 991 fail (`tests/guide_contract.lua:770,772,1435`):
  `gather: cs_remaining from the client cooldown (got 0, want 4)`,
  `gather: cs_duration latched from the client cooldown (got nil, want 4)`,
  `judge_remaining (got 0, want 7)`, `judge_duration (got nil, want 8)`,
  `parity case cb: SnD riding with BF cooling prompts Cold Blood (got bf, want coldblood)`.
- `tests/druid_guide_state.lua` — 2 of 95457 fail (`tests/druid_guide_state.lua:2886,2887`, counter at :921):
  `gather: an unresolved Mangle rank yields no cost (got 35, want nil)`,
  `an unresolved rank skips the cost query entirely (got 1, want 0)`.
- `tests/shaman_guide_state.lua` — 13 of 838 fail (`tests/shaman_guide_state.lua:1131,1261,1264` et al.):
  weave icon `403 vs 25449`, `icon_lb_r1 vs icon_lb`, `weave_available false vs true`,
  SS/FN cooldowns `0 vs 8/15` + lengths nil, Fire Nova / shock filler answers `0 vs 1`.
- luacheck: **9 warnings / 0 errors** (76 files; count flickered 8/10/9 across runs —
  nondeterministic total line, per-file set stable): `classes/druid.lua:84,85`
  (unused `CLAW_NAME`, `SR_NAME`) +2 more in druid; `classes/paladin.lua:172`
  (unused `is_spell_known_query`); `classes/shaman.lua:151,153`
  (unused `WEAVE_EARTH_SHOCK_NAME`, `WEAVE_WINDFURY_TOTEM_NAME`);
  `compat.lua:36` (unused `addon_name`); `main.lua:77` (`table.pack` undefined field).
  Journal floor claims 2/0 — the tree is ABOVE floor. Pattern matches journal:170
  parallel-writer crossfire (suites that pin class modules vs mid-flight class edits).
  Reconciliation owner: orchestrator. Per-client API verdicts below are unaffected
  (all API-surface suites — smoke, secret_guard, swing_source, main_init, toc_check — PASS).

## 1. Per-family API truth table (source-cited)

Notation: VERIFIED = cited branch:file:line · UNVERIFIED = not decidable from lua source
(natives are engine-side; in-client check owed) · OPERATOR = operator-confirmed in-game.

| API | Era/SoD (`classic_era`) | TBC Anniv (`classic_anniversary`) | Wrath Titan (`classic_titan`) | Forever (`origin/forever`) | Retail (`live`) |
|---|---|---|---|---|---|
| Family detect (`WOW_PROJECT_ID`) | 2 (`…/FrameXMLBase/Cata/Constants.lua:136`) | 5 (`:137`, BURNING_CRUSADE) | 11 (`:138`, WRATH) | 18 via `WOW_PROJECT_CAMELOT` (`…/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua:1-2`: `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT`) — no `WOW_PROJECT_FOREVER` global exists anywhere; compat's local derivation is consistent | 1 (`:135`, MAINLINE). CATA=14, MISTS=19 (`…/Cata/Constants.lua:126-127`) |
| Interface fallback | 11509 (toc_check pins) | 20506 | 38002 | 16001 → FOREVER, never Era (compat.lua:79-82) | 120100/120105 |
| `GetSpellInfo` global | NATIVE (no lua def on any branch — `git grep "^GetSpellInfo\s*="` empty). Id-form call sites: `…/Blizzard_Collections/Classic/Blizzard_MountCollection.lua:641` | NATIVE, same (identical file/line +CRLF) | NATIVE, same | Bare-global calls exist ONLY in `Classic/`-variant files (`…/Blizzard_Commentator/Classic/…:401` etc.) that do not load on Mainline-code clients; live `Mainline/` code uses `C_Spell` exclusively | Same as Forever |
| `C_Spell.GetSpellInfo` | `SpellIdentifier` = id OR name OR link (`…/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:190-197`, identical all 5 branches) | same | same | same + `SecretArguments` | same + `SecretArguments` |
| `GetSpellCooldown` global | NATIVE. Only in-source call form on ALL classic branches: `(slot, bookType)` — `…/Blizzard_UIPanels_Game/Classic/SpellBookFrame.lua:324` (era/anniversary/titan byte-identical modulo CRLF). Single-arg id/name form NEVER exercised by Blizzard UI | same | same | n/a (Mainline code: `C_Spell.GetSpellCooldown` only — `…/UIPanels_Game/Mainline/WorldMapActionButton.lua:110`) | same as Forever |
| `C_Spell.GetSpellCooldown` | `spellIdentifier`, `MayReturnNothing` (SpellDocumentation.lua:108-120, all 5) | same | same | same + `SecretWhenCooldownsRestricted` | same + `SecretWhenCooldownsRestricted` |
| `IsSpellKnown` global | CVar-gated shim `IsSpellKnown(spellID, isPet)` → `C_SpellBook.IsSpellInSpellBook` (`…/Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua:14-18`, identical all 5 incl. forever/live). Native provision UNVERIFIED | same | same | same file; native provision UNVERIFIED | same |
| `C_SpellBook.IsSpellKnown` / `IsSpellKnownOrOverridesKnown` | NOTE: these live in `C_SpellBook`, NOT `C_Spell` — `…/SpellBookDocumentation.lua:82-96` (`spellID:number`, all 5). `C_Spell.IsSpellKnown*` appears NOWHERE in any branch's generated docs — compat.lua:184-191 probes miss on every client and fall through to the classic global / `C_SpellBook` exactly as the chain intends (verified harmless, but the comment's namespace attribution is wrong) | same | same | same + `SecretArguments` | same + `SecretArguments` |
| `UnitAura` global | CVar-gated shim over `C_UnitAura
...[truncated 8903 chars]

## 2. Gap dispositions — verification lane 2026-10-19 (ses_perclient-gaps; read-only, `git show <branch>:<path>` throughout, checked-out branch untouched)

**Blocking record:** the G1–G8 gap list itself did not survive on the bench — the file ends mid-table
at line 52 with the literal marker above (on disk since 13:46). No brief exists for the perclient-audit
lane, no desk journal holds the list, memory search returns nothing. Three gaps were recoverable because
the compat-audit-fixes lane quoted them from its dispatch objectives
(`desks/compat-audit-fixes/journal.md:4`); the other five numbers are unrecoverable from any bench,
journal, brief, or memory source. They are marked UNVERIFIABLE below with exactly what is missing.
Notation: CONFIRMED = verified against branch source just now · UNVERIFIABLE = not decidable, reason given.
All branch citations re-verified this lane; several audit citations are refined (values hold).

### Recovered gaps (quoted from desks/compat-audit-fixes/journal.md:4) — all CONFIRMED, fixes already landed, no new build owed

- **GAP-1 — `C_Spell.IsSpellKnown*` dead probes: CONFIRMED (bug).** The literal `C_Spell.IsSpellKnown`
  appears NOWHERE on any branch (`git grep` empty on classic_era/classic_anniversary/classic_titan/
  origin/forever/live). The live namespace is `C_SpellBook`: SpellBookDocumentation.lua head declares
  `Namespace = "C_SpellBook"` (era + live), with `IsSpellKnown` at :82 (era) / :684 (live) and sibling
  `IsSpellKnownOrInSpellBook` beside it. Fix direction already built: compat.lua:184-204 probes the
  classic global first, then `C_SpellBook.IsSpellKnown` + `IsSpellKnownOrInSpellBook`, with the comment
  documenting the absence (ses_eaab3285, pins in tests/secret_guard_state.lua + tests/smoke.lua).
- **GAP-2 — `cleu_supported` shim gate: CONFIRMED (bug).** Deprecated_CombatLog.lua defines
  `CombatLogGetCurrentEventInfo = C_CombatLog.GetCurrentEventInfo` at :18 on ALL 5 branches
  (loadDeprecationFallbacks-gated), so the probed global exists on Forever/Retail with no classic
  combat log behind it. CLEU itself is engine-side: it appears in lua ONLY as a CallbackEvent in
  CombatLogDocumentation.lua (`LiteralName = "COMBAT_LOG_EVENT_UNFILTERED"`), with zero
  `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` call sites on any branch. Fix direction already
  built: compat.lua:1013 `st.cleu_supported = get_combat_log_event_info ~= nil and not st.is_mainline`.
- **GAP-3 — `C_ShapeshiftForm` dead probe: CONFIRMED (bug).** `C_ShapeshiftForm` appears NOWHERE on
  any branch (`git grep` empty x5); the bare `GetShapeshiftForm` has no lua definition anywhere
  (native). Fix direction already built: compat.lua:739-747 bare-global-first else 0. Refinement (no
  change owed): the compat comment says RestrictedEnvironment.lua allowlists it "on
  era/anniversary/titan" — it is allowlisted at RestrictedEnvironment.lua:83 on ALL 5 branches
  (allowlist ≠ provision; code path identical).

### §1 truth-table claims — re-verified with corrected citations

- **Family detect values CONFIRMED, citations REFINED.** Values hold: CLASSIC=2, BURNING_CRUSADE=5,
  WRATH=11, MAINLINE=1, CATA=14, MISTS=19, CAMELOT=18. But the audit cites the SHARED
  constant-definition lines in `Blizzard_FrameXMLBase/Cata/Constants.lua` (era:135-140,
  live/forever:122-127 — identical across branches), not client identity. Actual per-client identity
  comes from the variant file each client loads: Vanilla:97 `WOW_PROJECT_ID = WOW_PROJECT_CLASSIC`
  (era), TBC:97 `= WOW_PROJECT_BURNING_CRUSADE_CLASSIC` (anniversary), Wrath:124
  `= WOW_PROJECT_WRATH_CLASSIC` (titan), Camelot/ProjectConstants.lua:1-2
  `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT` (forever). Constant names carry
  the `_CLASSIC` suffix (`WOW_PROJECT_BURNING_CRUSADE_CLASSIC` etc.), not the audit's bare shorthand.
  `WOW_PROJECT_FOREVER` exists on NO branch (empty x5) → compat.lua:47 local derivation
  (`WOW_PROJECT_CAMELOT or 18`) is the only source: CONFIRMED, no change (compat.lua:51-65,77-94
  already use these names).
- **`GetSpellInfo` global NATIVE: CONFIRMED** (`^GetSpellInfo\s*=` empty x5). Refinement: the cited
  id-form call site (MountCollection :641) sits INSIDE a `--[[ ]]` comment block; live id-form calls
  are at :553/:573/:624. Same conclusion.
- **`C_Spell.GetSpellInfo` id-or-name: CONFIRMED** (SpellDocumentation GetSpellInfo block:
  `spellIdentifier` = "Spell ID, name, name(subtext), or link", era :~197; `SecretArguments` 63 hits
  forever / 60 live / 0 era).
- **`GetSpellCooldown` slot-form: CONFIRMED** at SpellBookFrame.lua:324 on all 3 classic branches
  (`GetSpellCooldown(slot, SpellBookFrame.bookType)`); era has two more bare-global sites, ALL 2-arg
  slot-form (Cata/SpellBookProfessions.lua:42, Mists/SpellBookFrame.lua:560). Single-arg id/name form
  NEVER exercised by Blizzard UI: CONFIRMED.
- **`C_Spell.GetSpellCooldown` docs: CONFIRMED** (SpellDocumentation GetSpellCooldown block:
  `MayReturnNothing`, `spellIdentifier` arg; `SecretWhenCooldownsRestricted` 6 hits forever+live, 0 era).
  WorldMapActionButton.lua:110 `C_Spell.GetSpellCooldown(self.spellID)` identical forever+live.
- **Forever/live bare-global confinement: PARTIALLY OVERSTATED (citation refinement, no behavior change).**
  Forever bare `GetSpellInfo(`: 8 Classic-variant sites + 1 REAL call in a Cata-variant file
  (`UIPanels_Game/Cata/PetStable.lua:321`, id-form; file present on all classic branches, ABSENT on
  live). Live bare `GetSpellInfo(`: Commentator/Classic/* (4 sites) + `TalentUI/Cata/Blizzard_TalentUI.lua`
  :673/:675/:842. So bare globals appear in Cata-variant files too, not only Classic/-variant ones.
  Which variant files a Mainline-code client actually loads is toc-driven and was NOT verified from lua
  source — in-client/TOC check owed if the claim matters. No addon change: compat probes globals at
  runtime, and the operator TBC-name rule (bench/lessons.md) stands on its own in-game confirmation.
- **`IsSpellKnown` shim: CONFIRMED** (Deprecated_SpellBook.lua `IsSpellKnown(spellID,isPet)` →
  `C_SpellBook.IsSpellInSpellBook` at :16-19 on anniversary/forever/live; audit's :14-18 is the same
  block; era/anniversary md5s differ by CRLF only).
- **`UnitAura` row: UNVERIFIABLE** — claim text lost to the truncation (row cuts at "CVar-gated shim
  over `C_UnitAura"). What's missing: the rest of the row (shim file, per-client verdicts).

### Unrecoverable numbers + stale §0

- **GAP numbers beyond the three above (i.e. G4–G8 or whichever numbers they carried): UNVERIFIABLE.**
  What's missing: the original gap text (the truncated ~8903 chars) or the dispatch objectives of
  ses_eaabf8ba6ffe5OcD3QHmpLXS9S. Five gaps' worth of definitions cannot be confirmed, denied, or
  cited from any source on disk. Ask: orchestrator to supply the dispatch objectives or rule the
  three recovered gaps + the refinements above as the substantive closure.
- **§0 harness RED (38 steps, 3 failed) + 9 luacheck warnings: STALE/SUPERSEDED.** Recorded pre-fix-wave;
  later lanes closed the named failures (hu5-rekeys fixtures, shaman-g1, hunter-distance, compat-fixes,
  etc.). Current harness state is owned by the orchestrator (validation owner).