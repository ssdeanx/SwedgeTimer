# Stale Claims — Journal

## 2026-10-20 — Desk opened
- **Purpose:** clear the last stale claims the final-gate fix wave left behind — the
  shipped comments and the one CHANGELOG passage that now contradict the code they
  describe.
- **Scope:** `CHANGELOG.md` (the "per-class sets" passage, lines 780-793), the comment
  lines only in `classes/hunter.lua`, `classes/druid.lua`, `classes/rogue.lua`, and the
  three class suites' stale-phrase pins **if** they need re-wording. Nothing else.
- **Source:** `bench/final_gate_fixes_2026-10-20.md` §5 "Filed for the orchestrator"
  (items 1 and 2) and `bench/final_gate_audit_2026-10-20.md` §6 C1 (the UNCONFIRMED
  classic-line name leg).
- **Rules:** comments state what the code DOES; every claim cites the tree or is marked
  UNCONFIRMED; no behaviour, no id, no resolution logic, no pin's behaviour expectation;
  CRLF preserved (`CHANGELOG.md`, `classes/hunter.lua`, `classes/druid.lua`,
  `classes/rogue.lua`); no git.
- **Next step:** read the three class files' sites, rewrite the CHANGELOG passage and the
  six comment sites, re-run the harness + luacheck, then journal and signal.

## 2026-10-20 — [signal:done] the CHANGELOG passage and the six comment sites now match the tree
- **Worked on:** rewrote `CHANGELOG.md:780-799` (the "per-class sets" passage) to the
  tree's truth — the **paladin** publishes one bucket per family (`sotc` on Era/TBC/
  WotLK/Forever, the same ten keys **without** it on Cata/Mists/Retail; the seal went
  away in 4.0) and the **shaman** is still flat; the four bucketless classes are now
  named (warrior, rogue, hunter, druid). Corrected the six false "rank art" comment
  sites: `classes/hunter.lua` (the `THE IDS` bullet + the resolver note),
  `classes/druid.lua` (same two), `classes/rogue.lua` (the drill-icon rule, the
  `THE IDS` bullet, the resolver note). Every rewording uses the wording the previous
  lane landed for the paladin/warrior/shaman, marks the classic-line name leg
  **UNCONFIRMED** (audit §6 C1), and says the cited id ladder is the citation and the
  fallback.
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings / 0 errors
  in 85 files** (the standing floor, both pre-existing). The three stale-phrase pins
  (`tests/paladin_state.lua:3599`, `tests/warrior_state.lua:5658`,
  `tests/shaman_state.lua:3704`) read paladin/warrior/shaman — **files this lane did
  not touch** — so they needed no re-wording and are unchanged. Mutation proofs on
  `/tmp/opencode/stale_claims_mut`: the old wording restored in each of the three
  files → each suite fails (2 of N checks, exit 1) → **3 kills, 0 escapes**, control
  green. CRLF kept (CHANGELOG 993/0, hunter 5363/0, druid 4639/0, rogue 3695/0 lone
  LF). Every edited line in the three class files is a comment; no behaviour, no id,
  no pin touched. Artifact: `bench/stale_claims_2026-10-20.md`.
- **Filed for the orchestrator (not edited — out of scope):** the same false claim
  survives at `classes/hunter.lua:4967`, `classes/druid.lua:4233-4234` and
  `classes/rogue.lua:2997` ("the NAME-first resolution finds the client's own rank")
  and at `practice_ui.lua:419-423` / `:508-512` ("Era, TBC and Forever each answer
  their own rank art"); the stale-phrase pins exist **only** for paladin/warrior/
  shaman, so nothing would catch a reintroduction in hunter/druid/rogue; and no suite
  reads `CHANGELOG.md`, so a doc regression there is invisible to the harness.
- **Next step:** the orchestrator validates (harness + luacheck owner) and decides
  whether to dispatch a follow-up lane for the five remaining sites and the three
  missing pins. This desk has nothing left to do.

## 2026-10-20 — [signal:done] the five remaining sites are cleared and the guard covers all six classes
- **Worked on:** resumed this desk for the follow-up the previous session filed
  (`bench/stale_claims_2026-10-20.md` §4 items 1-3). Cleared the false
  "the NAME-first resolution finds the client's own rank" claim in the three
  `FOR THE RECORD` notes (`classes/hunter.lua:4966-4971`,
  `classes/druid.lua:4233-4238`, `classes/rogue.lua:2996-3001`) and the
  "Era, TBC and Forever each answer their own rank art" claim in the two
  `practice_ui.lua` drill-icon notes (`:419-425`, `:510-516`) — all now state
  the house truth: the **name** leg is primary and **UNCONFIRMED in-client**
  (audit §6 C1), the **id table is the citation and the fallback** (the ERA
  rank-1 id; the client's own rank only where that id still exists — the
  Healthstone's 5720 answers "Not Found" on Cata/Mists). Added the missing
  **source-shape comment pins** to `tests/hunter_state.lua:5154-5186`,
  `tests/druid_state.lua:3990-4022`, `tests/rogue_state.lua:3821-3853` and
  `tests/practice_ui_state.lua:6159-6197` (four checks each: the house stale
  phrase absent, the file-local stale phrase absent, the house marker present,
  the corrected statement present; `practice_ui.lua` uses a **count** so both
  drill sites must carry it). The pins match on **prose**, not on source lines,
  because the claim is wrapped across three lines in each class file.
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings /
  0 errors in 85 files** (the standing floor, both pre-existing).
  **6 mutation kills, 0 escapes** on `/tmp/opencode/stale_claims_guard_mut`
  (M1-M3 the stale phrase back in each class file, M4 the shaman drill note
  back, M5 the rogue drill note back, M6 the house stale phrase dropped into
  the hunter) — every one turns its suite red; the control run is green.
  **No behaviour changed, proven mechanically:** the pre-edit and post-edit
  `luac5.1 -l -l` listings of all four source files are byte-identical once
  the source line numbers and the heap addresses are normalised. `practice_ui.lua`
  is still at 199 file-scope locals. CRLF kept in all four source files; the
  test files are LF. Artifact: `bench/stale_claims_guard_2026-10-20.md`.
- **Filed for the orchestrator (not edited — out of scope):** **one** false
  claim is left in the tree, `classes/warrior.lua:4899` — the same
  `FOR THE RECORD` note the previous lane missed in the warrior (it corrected
  the warrior's `THE IDS` bullet and its resolver note, not this note). It is
  in a file this lane was explicitly forbidden to touch, so it is filed with a
  hands-up signal; the fix is this lane's wording plus one more check in
  `tests/warrior_state.lua`. The CHANGELOG still has no mechanical pin
  (carried over).
- **Next step:** the orchestrator validates (harness + luacheck owner) and
  decides whether to dispatch the one-line warrior follow-up. Nothing else is
  left in this desk's scope.

## 2026-10-20 — [signal:hands-up] the last false claim is in a file this lane may not touch
- **Raised:** `classes/warrior.lua:4899` — the `FOR THE RECORD` note still reads
  "the NAME-first resolution finds the client's own rank", the same false claim
  this lane cleared in the hunter, the druid and the rogue. `classes/warrior.lua`
  is on this lane's do-not-touch list, so it is **filed, not fixed**.
- **Why it matters:** it is the ONLY remaining instance in the six classes (the
  four classes with no Cata/Mists bucket are exactly the four that carry the
  note). The brief's done-criterion ("no site carries the false claim") cannot
  be met inside the brief's scope.
- **Evidence:** `bench/stale_claims_guard_2026-10-20.md` §4 item 1; the
  machine-readable copy is
  `desks/stale-claims/.signals/2026-10-20T225600Z.json`.
- **Next step:** the orchestrator rules — a one-line follow-up (this lane's
  wording + one more check in `tests/warrior_state.lua`) closes it.
