# changelog-truth — Journal

## 2026-10-20 — Desk opened
- **Purpose:** make `CHANGELOG.md` true against the tree — close the documentation-truth
  audit's F6/F7/F8/F14/F15/F16/F17 against the code, and add the entries the last two
  waves shipped (neutral actions, family scope, HUD ids, progression, contracts).
- **Scope:** `CHANGELOG.md` only, plus one new bench artifact
  (`bench/changelog_truth_2026-10-20.md`). No `.lua`, no `README.md` / `TESTING.md` /
  `bench/live_test_script_2026-10-19.md` (a sibling lane owns those), no other bench
  file, no TOC, no version, no git, no lint-config change.
- **Evidence bar:** every claim re-read in the tree before it is written down; the
  bench citation travels with it; nothing claims in-client proof (every new row is
  "verified offline, UNCONFIRMED in-client"); no invented ids, names or URLs.
- **Next step:** read `desks/docstruth-audit/journal.md` (F6/F7/F8/F14/F15/F16/F17) and
  `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0, then fix the changelog in place.

## 2026-10-20 — the CHANGELOG truth pass (done)
- **Worked on:** `CHANGELOG.md` only, plus one new bench artifact
  (`bench/changelog_truth_2026-10-20.md`, verified absent before it was written) and this
  desk's journal + signal. **No `.lua` touched** — verified: the harness is byte-identical
  at 43 steps / 0 failed and luacheck 2/0 in 85 files after the edits, and the only
  `.lua` mtimes in the tree are other lanes'. `README.md`, `TESTING.md` and
  `bench/live_test_script_2026-10-19.md` were NOT touched (a sibling lane owns them). No
  other bench file, no TOC, no version, no git write, no lint-config change.
- **The seven findings, closed against the tree** (every claim re-read in the code, not
  taken from the audit):
  * **F6** the paladin pre-pull names were wrong: the tree's own
    `ST.PALADIN.practice_prepull_rows` labels **20920 = Seal of Command** and
    **20308 = Seal of the Crusader** (the changelog had "Divine Storm 20920" and
    "Holy Shock 20308"). Divine Storm is 407778 (SoD) / 53385 (WotLK) and Holy Shock is
    20930 in this tree — neither is a row of that table. The eleven-row count was
    re-counted and stands.
  * **F7** the warrior publishes **six** drills, so the "the warrior included" parenthetical
    was dropped and the sentence now says the warrior is not one of them.
  * **F8** the design registry is 13 targets — **14 on a druid** (the Combo Points pips
    register a fourteenth).
  * **F14** the "Correction to the earlier release notes" notice about the druid
    "stating none" was **void** (the entry it corrected was already fixed in the same
    document); it is now a dated history note — nothing was deleted from the record.
  * **F15** the shipped copy is "Multi-target mode (manual, not wired yet)", not
    "(future)".
  * **F16** the two strings are **different** ("Practice scenario is not available on this
    client (no live swing engine)." vs "The rotation scenario cannot run on this client
    (no live swing engine)."); each is now quoted exactly and the changelog says they are
    two strings for one behaviour.
  * **F17** "pips 10->12" matches no shipped number (the row is **five** 10 px cells on a
    12 px step) — dropped from both bullets.
- **The new wave entries** (a new dated section appended inside `[2.1.1]`, after the
  Audit-fix wave; no existing section was rewritten): the NEUTRAL action (engine) and the
  four published per-class sets, the shaman's family-scoped rotation and slots, the
  hunter's family-correct HUD ids (and the **Forever 7-slot** row), the six progression
  fixes, the drill-list pick contract, the pre-pull contract suite, and the sibling lane's
  documentation-truth corrections. Each carries its bench citation and the "verified
  offline, UNCONFIRMED in-client" marking. The section's offline state is the current
  tree: **43 steps / 0 failed, luacheck 2 warnings / 0 errors in 85 files**.
- **Numbers taken from the tree, not from the bench files** (the bench had moved on):
  the hunter's HUD slot counts are **Era base 6, Era/SoD 7, TBC 9, WotLK 9, Forever 7,
  Cata 9, Mists 8, Retail 9** (the bench file said "CATA/MISTS/RETAIL 9" — the Mists
  count is 8 in the tree), and the four neutral sets are **larger** than the class lane's
  first list (the common abilities were added by the follow-on lane) — so the changelog
  quotes the shipped tables, not the earlier bench snapshots.
- **Raised, not papered over:** the tree disagrees with itself on the **SoD** 20920
  pre-pull row — the pre-pull table labels it "Seal of Command" and the `sob` rotation
  row's source comment calls the same SoD 20920 r5 "Seal of Martyrdom" (that row's own
  SoD id is 407798). The changelog follows the pre-pull table and says so; the code-side
  label is filed for the owner in the bench file (§4 item 1). **This lane changed no
  `.lua`.**
- **Hygiene:** `CHANGELOG.md` stays **CRLF** (982 of 983 lines; the last line has no
  terminator, pre-existing). No tab, no trailing whitespace on any touched line. The new
  bench file is LF, the convention the other 2026-10-20 bench files use.
- **Current state:** the changelog is true against the tree line by line for the seven
  findings, and the last two waves are recorded with their citations. Nothing in it
  claims in-client proof.
- **Next step:** the orchestrator validates `CHANGELOG.md` and
  `bench/changelog_truth_2026-10-20.md` in-tree. Open: the F6 SoD label (code side), the
  hunter's and the druid's neutral sets (not landed), F18 (out of scope), the version bump
  (the operator's call). **Validation owner: orchestrator.**

