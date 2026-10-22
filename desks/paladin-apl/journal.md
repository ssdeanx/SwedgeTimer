# paladin-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Build the paladin's missing APL rotation lines (the utility layer
  the other five classes just received) into `ST.PALADIN.practice_rotation`
  with the APL priority citations, the per-family spell id + name, the family
  gates and the HU-13 two flags (`live` = the read exists, `engine` = the
  frozen engine has an arm) — and give the frozen engine (`nextaction.lua`) an
  arm for each so the practice scenario can ask for it and the guide can light
  it.
- **Scope:** `classes/paladin.lua`, `nextaction.lua`, `tests/paladin_state.lua`,
  `tests/nextaction_state.lua`, `tests/guide_contract.lua` (the paladin section
  only). One new bench file. No git, no lint-config change, no TOC/version/
  option change, no other class touched.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` §6 (the
  paladin) — but the **gap analysis is the input, not the authority**: every
  APL was re-fetched on 2026-10-20 from
  `raw.githubusercontent.com/wowsims/{classic,sod,tbc-new,forever,wotlk}/master`
  and every id/name was re-checked against the sims' own spell data and the
  1.15 client's own spell tables. **The paladin section of the gap analysis
  carries four errors** (see §3 of the bench report).
- **Next step:** re-verify every id/index against the APL JSON, write the
  rotation rows + the pre-pull table (HU-12), add the engine arms, pin them in
  the three suites, prove the mutations on `/tmp/opencode` copies.

## 2026-10-20 — The APL utility layer landed
- **Worked on:** re-fetched all ten paladin APL files (Era `basic_ret`; SoD
  `p8-twist`, `p8-exodin`, `p8-stack`, `p8-shockadin-1h`, `p8-shockadin-2h`,
  `p8-wrath`; TBC `default`; Forever `twist_of_light` + `holy_shock`; WotLK
  `default`) and expanded every `groupReference` inline, so the indices below
  are the full priority order. Cross-checked the names against the sims' own
  spell tables (`spell_data_auto_gen.go`), the per-ability `.go` files and the
  1.15 client's own `SkillLineAbility.csv` / `Spell.csv`.
  Landed: **five** rotation rows in `ST.PALADIN.practice_rotation` (the shipped
  12 rows now carry both flags too), **two** engine arms
  (`nextaction.lua`'s `FCFS_ORDER_WRATH` utility band + the `hor` / `how_wrath`
  eligibility and remaining arms), **two** new guide slots (ten → twelve, the
  count pin re-cut), the **pre-pull table** grown from 2 rows to 11 (HU-12),
  and the practice key space taught the two new presses.
- **Corrections to the corpus (four, all proved against the sources):** 20216
  is **Divine Favor**, not Devotion Aura; 53408 is **Judgement of Wisdom**,
  not Judgement of Light; 20375 is **Seal of Command** on the Era client (the
  gap analysis called it Seal of the Crusader); 10301 is **Retribution Aura**,
  not Redemption. The corpus's "Purity 16322" (SoD) is a **dead row** — 16322
  is absent from the 1.15 client's own spell tables.
- **Filed, not built:** the WotLK Judgement of Wisdom arm (it shares the 10 s
  judgement cooldown with the shipped Judgement of Light row, so an arm would
  displace the shipped cue), the Forever Holy Strike arm (no cooldown of its
  own — arming it re-cuts the Forever twist order), the Forever Divine Favor
  arm (the APL's own condition needs reads the tree does not have, and an arm
  built on the cooldown alone could ask for a buff that is up).
- **State:** the full harness is green (41 steps, 0 failed), luacheck holds the
  floor (2 warnings / 0 errors in 83 files), 14 / 14 mutations killed on
  `/tmp/opencode` copies, CRLF preserved in `classes/paladin.lua` and
  `nextaction.lua` (the three test files stay pure LF).
- **Next step:** the orchestrator validates; the operator rules on the two
  operator-visible items the bench report files (the WotLK order re-cut and the
  WotLK HUD mirror for the two new slots).

## 2026-10-20 — [signal:hands-up] the WotLK order re-cut needs the operator's ruling
- The lane armed the WotLK APL's utility band (Hand of Reckoning 67485 = the
  APL's i=1, Hammer of Wrath 48806 = i=2) ABOVE the shipped damage rows, so
  the WotLK guide prompts those two while they are up. The shipped damage
  rows (cs, judge, ds, cons, exo, hw) keep their relative order and the
  shipped Judgement and Holy Wrath rows stay where they were — but the WotLK
  APL has no row for either.
- The full APL re-cut (hor, how_wrath, jow, cs, ds, exo, cons — which would
  also drop the shipped judge/hw rows) is the operator-visible change the
  corpus filed (§6.5); the lane did NOT do it.
- The Judgement of Wisdom arm (53408) is filed behind that ruling: it shares
  the 10 s judgement cooldown with the shipped Judgement of Light row, so an
  arm would replace the shipped cue.
- Signal file: `desks/paladin-apl/.signals/2026-10-20T05-05-00Z.json`. The
  orchestrator owns the human row in `hands-up.md`.

## 2026-10-20 — [signal:done] the APL utility layer landed
- The rotation table carries the APLs' utility layer (five new rows, both HU-13
  flags on every row); two rows are armed in `nextaction.lua` and light two new
  guide slots; the pre-pull table carries all eleven APL pre-pull rows.
- Four corpus corrections and one dead row are proved in
  `bench/paladin_apl_utility_build_2026-10-20.md` §3.
- Harness 41/0, luacheck 2/0 (the floor), 14/14 mutations killed.
- Signal file: `desks/paladin-apl/.signals/2026-10-20T04-58-00Z.json`.

## 2026-10-20 — Desk closed (the lane is landed)
- **Summary:** the paladin's rotation table now carries the APLs' utility
  layer with cited, family-gated rows and both HU-13 flags; two of them
  (Hand of Reckoning 67485, Hammer of Wrath 48806) are armed in the frozen
  engine, ride the WotLK FCFS order and light two new guide slots; the other
  three ship with the exact read they wait for in `needs`. The corpus's four
  paladin errors are corrected in place, and the APL's pre-pull rows live in
  the pre-pull table (HU-12), never in the combat rotation.
- **Artifacts:** `bench/paladin_apl_utility_build_2026-10-20.md` (the report,
  the evidence and the filed items).
- **Handoff:** the operator's two open rulings — (1) the WotLK order re-cut
  (the full APL priority list, which would replace the shipped
  `cs, judge, ds, cons, exo, hw` damage order with the APL's
  `hor, how_wrath, jow, cs, ds, exo, cons`), and (2) the WotLK HUD mirror for
  the two new guide slots (the HUD suite owns that pin; this lane did not
  touch `hud_state.lua`). Until (1) is ruled, the shipped damage rows keep
  their relative order and the utility band sits above them.
