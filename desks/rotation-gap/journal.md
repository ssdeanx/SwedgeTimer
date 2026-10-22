# Rotation Gap vs APL — Journal

## 2026-10-20 — Desk opened
- **Purpose:** read-only comparison of every class's SHIPPED rotation table
  (`ST.<CLASS>.practice_rotation`) against the wowsims APLs (classic, sod,
  tbc-new, forever, wotlk), to find the rotation lines the shipped table is
  MISSING — the operator's named case: the warrior rotation carries the damage
  abilities (op/execute/slam/bt/ww/ms/...) but no utility set (Charge, Battle
  Stance, Berserker Stance, Blood Rage, ...). A rotation that only carries the
  damage abilities is not the class's rotation.
- **Scope:** read-only across the addon tree. The ONLY bench file written is
  `bench/rotation_gap_vs_apl_2026-10-20.md` (verified absent by glob before
  writing). No addon file, no test file, no other bench file, no git.
- **Deliverable per class (six):** current action keys; the APL priority list
  with citations (file + action index); the missing-line specs (action key,
  spell name + id per family, family gate, probe requirement); the
  correctly-absent list.
- **Next step:** read the six shipped rotation tables, fetch the five families'
  APLs, diff, write the bench file, then journal + signal.

## 2026-10-20 — Gap analysis complete, bench file written
- **Worked on:** read the six shipped `ST.<CLASS>.practice_rotation` tables
  (warrior `classes/warrior.lua:3636-3746`, hunter `classes/hunter.lua:2815-2906`
  + prepulls `:2921+`, rogue `classes/rogue.lua:2174-2271`, druid
  `classes/druid.lua:2826-2950`, shaman `classes/shaman.lua:4116-4189`,
  paladin built from `classes/paladin.lua:4146`+`nextaction.lua:953-982`);
  fetched 30 APL files from `wowsims/{classic,sod,tbc-new,forever,wotlk}`
  (master), expanded every `groups` block inline so the priority list is the
  real order, and diffed each table against it.
- **Artifact:** `bench/rotation_gap_vs_apl_2026-10-20.md` (1.2 k lines) — per
  class: current keys, the APL priority list with `repo path [index]`
  citations, the missing-line specs (name + id per family, family gate, APL
  position, probe: existing compat wrapper vs NEW), the correctly-absent list,
  and the priority-position conflicts.
- **Current state:** the operator's warrior case is confirmed and wider than
  stated — all six tables are missing a utility layer (warrior: no stance, no
  shout, no Bloodrage, no Recklessness, no Death Wish; paladin: no Hor/How/jOL
  on WotLK; hunter: no Serpent/aspect/utility upkeep line; rogue: no
  Vanish/Preparation/Cloak/Shadowstep; druid: no Cat Form/Leader of the Pack;
  shaman: no Strength of Earth / Nature's Wrath / Frost Shock / weapon-imbuff
  rows). **Zero new client APIs are needed** — every probe is an existing
  `compat.lua` wrapper (§0.5 of the file).
- **Two corrections to earlier bench claims**, both in the file: (1) the
  operator's "Blood Rage is a WotLK warrior ability" is wrong for the sim's
  Bloodrage 2687, which is in all five families' APLs; (2) the shipped warrior
  `hamstring` row's 18499 is **Berserker Rage**, not "Improved Hamstring" (the
  sim's own file names it).
- **Also found:** `wowsims/wotlk` was not in the earlier rotation audits, and
  it changes the paladin's Wrath order (the APL's top two rows — Hand of
  Reckoning, Hammer of Wrath — are absent from the shipped order, and the
  order's `hw` = Holy Wrath is not a WotLK APL row at all).
- **What did not work / traps recorded:** the GitHub REST API rate limit
  (60/hr unauthenticated) was exhausted mid-session; the GitHub **HTML** tree
  pages (`github.com/<repo>/tree/master/sim/<class>`) work and were used
  instead. Wowhead rate-limited to 403 after ~60 requests, so spell names come
  from the sim's own spell data (`spell_data_auto_gen.go`, per-ability `.go`
  files) — which is also the only version-correct source, because spell ids are
  reused across clients (25289 = Battle Shout in TBC/Forever; 20375 = Seal of
  the Crusader on Era/SoD, Seal of Command on TBC; 9850 = Claw on Era, Mangle
  on TBC/Forever).
- **Next step:** the operator/orchestrator decides which lines to build. The
  file's §7.5 gives a build order; the open UNCONFIRMED ids are listed in §7.4
  and each needs an in-client or source check before a row is written.

## 2026-10-20 — [signal:hands-up] HU-12 raised: what counts as "the rotation"
- **Worked on:** raised **HU-12** in `hands-up.md` and emitted the
  `escalation/hands-up` signal. The operator's premise ("a rotation that only
  carries the damage abilities is not the class's rotation") is confirmed and
  wider than stated, but every fetched APL mixes three row classes:
  (a) spell-decision rows, (b) sim-harness rows (`autocastOtherCooldowns`,
  `castAllStatBuffCooldowns`, the `Engineering` / `CD: Trinkets` /
  `CD: Racials` groups, the potion rows, the `Powershifting` group) and
  (c) pre-pull rows (Charge/Intercept, Aspect of the Hawk, Sanctity Aura,
  Battle Shout, Strength of Earth).
- **The question:** does `ST.<CLASS>.practice_rotation` become the APL's SPELL
  rows only (with a per-class prepull table, the shape
  `ST.HUNTER.PRACTICE_PREPULLS` already uses), or the FULL APL including
  consumables? The operator's own example lines (Charge, Battle Stance, Blood
  Rage) sit on the prepull/upkeep side of the split, so the ruling decides
  where they land.
- **Desk's recommendation (advisory, not a decision):** option (i) — the
  rotation table keeps the APL's spell-decision rows, a prepull/upkeep table
  takes the prepull and utility rows, and the sim-harness rows stay out of
  both.
- **Current state:** not blocked. The bench file lists the APL rows three ways
  per class, so either build can start from it.
- **Next step:** the operator rules; the orchestrator reconciles HU-12 into the
  lane plan.
