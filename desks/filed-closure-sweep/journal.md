# Filed Closure Sweep — Journal

Desk: `filed-closure-sweep`. Phase 6 of `bench/final_completion_plan_2026-10-19.md`.

## 2026-10-19 — Desk opened
- **Purpose:** Re-examine EVERY item filed "with reason" across the pre-publish wave and
  decide, per item, whether it is now **CLOSABLE** (with the exact source that closes it)
  or **STILL-FILED** (with a sharper, testable reason). Group the closable ones into
  disjoint build specs (file + exact change + pin + owning lane).
- **Scope:** Read-only research over `bench/` corpus (`deep_audit`, `class_features_drills`
  §5, per-lane filed lists, `ids_research`, `live_test_script`) plus read-only
  `git show <branch>:<path>` reads of `/home/sam/wow-ui-source` for client-API truth.
  One new output file only: `bench/filed_closure_sweep_2026-10-19.md`.
- **Out of scope:** addon/test/bench edits other than that one new file; git writes;
  editing class files; touching files a running lane owns; inventing ids or sim numbers.
- **Next step:** read the full corpus of filed lists, then write the sweep file.

## 2026-10-19 — The filed-item closure sweep is written
- **Worked on:** Phase 6 of `bench/final_completion_plan_2026-10-19.md` — re-examined every
  item filed "with reason" across the wave and gave each a CLOSABLE / STILL-FILED row with
  evidence. Read: `deep_audit` (F1–F14 + the justified exceptions), `class_features_drills` §5
  (U-01…U-15), the six per-lane filed lists (shaman slots/drills, hunter rotation-drills,
  warrior practice, druid drills, rogue drills-rotation, paladin practice-contract),
  `ids_research` (U1–U17), `live_test_script` §8 (U1–U17). Evidence: the shipped tree
  (read-only, in-tree anchors), the client source of five branches in
  `/home/sam/wow-ui-source` (read-only `git show`/`git grep`), and live fetches of the
  wowsims tbc-new / sod / classic / wotlk sim files and the wowhead slugs.
- **Current state:** `bench/filed_closure_sweep_2026-10-19.md` written (NEW; 157 rows across
  five corpora: **41 CLOSABLE**, **50 CLOSED**, **47 STILL-FILED** with sharpened reasons, plus
  9 build specs / 7 operator decisions / 7 new corpus findings). Nothing else was touched:
  no addon file, no test file, no other bench file, no TOC, no version, no `Libs/`, no git
  write. Desk footprint = this journal + `desks/filed-closure-sweep/.signals/`.
- **Notable closures (evidence, not vibes):** the shaman CoE id **66842** and the **water-totem
  slot 3** are in the shipped client's own `Constants.lua` (classic_titan 3.80.2);
  `api.GetInventoryItemID` already exists in `compat.lua` and `GetInventoryItemID` is in every
  branch's FrameXML with `INVSLOT_HEAD = 1` in the client's `Constants.lua` (so the druid's
  Wolfshead "no honest probe" comment was a false premise); `api.UnitAura(unit, …)` is already
  unit-generic (so the hunter's Serpent debuff is a missing scan, not a missing API); the
  rogue's "Hemo" is **Hemorrhage** and the bench's TBC ids are **swapped** (26862 = Sinister
  Strike, 26864 = Hemorrhage); the SoD p4-twist APL path is fetched and 200-OK.
- **Dead ends (do not repeat):** the wowsims warrior models contain **no** rage-regeneration
  term (classic/sod/wotlk checked) — a sim citation for the 10/s rage model is *impossible*, not
  merely missing; the classic clients' FrameXML contains **no** Chain Lightning code at all
  (the enemy-count sensor has no client contract); wowhead `/forever/` pages are bot-walled to
  this session's scraper (403) — the ids_research snippets stand; the tbc-new/sod APL paths
  are `ui/specs/<class>/<spec>/apls/` and `ui/<class>_<spec>/apls/` (the corpus's
  `ui/paladin/apls` and `ui/shaman/apls` guesses 404).
- **Next step:** the orchestrator validates the sweep in-tree, then dispatches the nine build
  specs **disjointly** — BS-1 (compat probes) first, because BS-2 and BS-3 depend on it; then
  BS-2/BS-3/BS-6 in parallel; then BS-4, BS-5, BS-7, BS-9, BS-8. Note the contention:
  `config_presets.lua` goes to BS-4c **or** BS-7, never both; the hunter/shaman class files
  were just written by the hunter-drills and shaman lanes, so the anchors must be re-read
  before dispatch. The 7 operator decisions in §10 (twist rank, the hunter/rogue slot budgets,
  the Chain Lightning count source, Devastate, the F13 trim measurement, the VR deferral) are
  not research-closable and need the operator.

## 2026-10-19 — [signal:done] The filed-item closure sweep is complete
- Signal: `desks/filed-closure-sweep/.signals/2026-10-19T23-05-00Z.json` (done).
- One new bench file: `bench/filed_closure_sweep_2026-10-19.md`. Every filed item in the corpus
  has a CLOSABLE / STILL-FILED row with evidence; the closables are grouped into nine
  disjoint build specs. Validation owner: the orchestrator.
