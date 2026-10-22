# Final publish-gate deep audit — 2026-10-20

Session `ses_ea50b69a7ffeT9t274D7oLIr6m` (read-only hunter lane; filed by the
orchestrator — the lane had no write tools). Tree state cited: **43 steps / 0 failed**,
**luacheck 2 warnings / 0 errors in 85 files**.

Scope: 43 addon `.lua` (37 root + 6 class modules) — 15 read in depth, 28 surveyed by
targeted sweep. ~97 error-handling/fallback locations reviewed. `Libs/`, `docs/`, `tests/`
excluded from the defect scope (tests read as evidence only).

**VERDICT: FINDINGS 8** — 3 HIGH, 3 MEDIUM, 0 LOW, 2 needing a ruling, 4 justified
exceptions. The publish gate (zero HIGH) was **not** met at this point; see §4 for the
orchestrator's independent verification, which changed the count.

---

## 1. Closed-item verdicts

| # | Closed item | Verdict |
|---|--------------|---------|
| 1 | Six-class practice scenario layer | PARTIAL → HIGH-1 (the grading path did not normalise the class's alias key space) |
| 2 | Per-class APL utility layer (live/engine flags, family gates, prepull tables) | CLOSED |
| 3 | Hold contract (HU-8) | CLOSED — the hold branch precedes the neutral branch, so a neutral press cannot dodge a hold |
| 4 | Neutral-action contract | PARTIAL → HIGH-1 (the class side normalises, the grader did not) |
| 5 | Neutral publish + offer gate | PARTIAL → HIGH-1 / J-1 (the gate covers the common list; the guide vocabulary is outside it) |
| 6 | Per-family rotation slices | CLOSED — no slice publishes a row its running family lacks |
| 7 | Prepull tables (no prepull row leaking into a combat rotation) | CLOSED — distinct `*_prepull` keys, separate table |
| 8 | Pick contract (the press cannot be shadowed by the class's published pick) | CLOSED |
| 9 | Progression fixes (cap floor, cap notice, account scope, streak readout, reset-arm expiry, NO_DAY sentinel) | CLOSED |
| 10 | Family-scoped HUD ids | CLOSED — one owner per surface |
| 11 | Shaman family-scoped rotation/slots | PARTIAL → MEDIUM-1 |
| 12 | Paladin family gate | CLOSED |
| 13 | Docs truth pass | PARTIAL → MEDIUM-2, MEDIUM-3, HIGH-2 |

## 2. HIGH findings

**HIGH-1 — the scenario grader compares raw press keys while the classification and
offer-gate layers normalise aliases → a correct press is graded F.**
`practice.lua:3685-3722` (`H.rotation_run_decide`), `practice_ui.lua:5152-5157`
(`scenario_cast`), `practice_ui.lua:4773-4804` (`scenario_action_order`),
`classes/paladin.lua:4313-4344` (the alias table), `:5790-5806` (`practice_filler_key`).
The paladin is the only class with two key spaces: the rotation engine says
`cons`/`exo`/`hs`/`am`, the guide slots say `consecration`/`exorcism`/`holy_shock`/
`aura_mastery`. The panel's action row pushes **both**, so the player gets two buttons for
Consecration — a bare text button (`cons`) and an icon button (`consecration`). The
scenario expects the canonical key; the press of the icon button is the raw alias → the
string comparison fails → `out_of_order` → **F**, streak break, 0 XP — on TBC, Forever,
Wrath and the four SoD orders. The offer gate and the closed-list test both normalise;
only the grader did not. Fix: one spelling per spell on the panel (canonical key, icon
resolved through the alias table) **and** the caller normalises the press before grading
(the engine stays pure).

**HIGH-2 — the "client's own rank art" claim is false.** The six new common-action
resolvers' `elseif type(spell_id) == "number"` branch was reported as dead code, and the
comments assert "every client family answers its own rank art". Fixing HIGH-1's
normalisation makes the branch reachable; the claim then has to be true or reworded.

**HIGH-3 — two files sit at Lua 5.1's 200-local ceiling (zero headroom).**
`classes/paladin.lua` = 200, `classes/warrior.lua` = 200; `classes/shaman.lua` = 199 and
`practice_ui.lua` = 199 (1 slot each). One more file-scope `local` in the paladin or the
warrior is a **load failure on every client** ("too many local variables"), not a test
failure. The harness's `luac5.1 -p` step catches it, but only if the harness runs. Fix:
move locals onto the module table (the paladin's own precedent: `APL_UTILITY`,
`practice_action_meta`, `practice_apl_rows`, `practice_prepull_rows`) and add a guard that
reports the headroom.

## 3. MEDIUM findings

- **MEDIUM-1** — the shaman's flat neutral publish is never widened onto the panel for
  Cata/Mists: `apply_family_slots` (`classes/shaman.lua:4970-4996`) returns **early** when
  the family has no rotation rows, so `apply_practice_panel_actions()` (`:4994`) is never
  reached. The other five classes call it from `post_init`. Fix: call it from `post_init`
  too.
- **MEDIUM-2** — the paladin's **flat** neutral publish carries `sotc` (Seal of the
  Crusader) on the 4.0+ clients, where the spell was removed in 4.0 — a dead button on
  Cata/Mists. Fix: family-scoped publish.
- **MEDIUM-3** — two shipped comments now contradict the code they describe:
  `classes/warrior.lua:4803-4821` says the common abilities "have NO key in the warrior's
  own ability list … publishing them would invent keys", while `:5041-5106` publishes
  exactly those keys.

## 4. Orchestrator's independent verification (changed the count)

The lane's **second HIGH finding** (an "off-by-one" `pcall(api.GetSpellInfo, …)` unpack at
seven sites) does **not** hold:

- `compat.lua:157-176` — `api.GetSpellInfo` returns **7** values
  (`name, rank, icon, castTime, minRange, maxRange, spellID`); the classic global is the
  client's own, the Retail wrapper maps the `SpellInfo` table onto the same 7, and the
  unknown-client fallback returns 7.
- `pcall` therefore yields **8** values, and every one of the seven sites declares **8
  names** (`local ok, spell_name, _, …, spell_id = pcall(api.GetSpellInfo, name)`) → the id
  lands correctly. The lane miscounted the names.
- The lane's own J-2 contradiction ("the ERA builder pin cannot pass") is settled by one
  run: `lua5.1 tests/rogue_state.lua` → **1095 checks, 0 failures**.

So: **2 HIGH remain** (HIGH-1, HIGH-3) and the unpack finding is a false positive. Both
remaining HIGHs were dispatched to fix lanes on 2026-10-20.

## 5. Rulings needed (open)

- **J-1** — the offer gate covers the **common-ability list**; the **guide-slot vocabulary**
  is offered on every family with no gate. On the four family-scoped classes the Cata/Mists
  panel offers the full guide vocabulary while the class publishes no rotation and no
  neutral bucket there. The presses are not punished (the step is UNKNOWN, so no attempt),
  but the panel is misleading. Ruling needed: does the gate extend to the guide vocabulary,
  and should a family with no published rotation offer the panel at all? The paladin and
  shaman publish a flat neutral set for Cata/Mists, so the two shapes disagree across
  classes.
- **J-2** — resolved by the run above (the rogue suite is green; the unpack is correct).

## 6. Per-client checklist for the orchestrator (shell access required)

`ast_grep_search` was used against `/home/sam/wow-ui-source` (checked-out branch
**classic_era**). It established that the classic **global** `GetSpellInfo` is called with
an **id** on classic-line clients
(`Interface/AddOns/Blizzard_ObjectAPI/Classic/Spell.lua:39`) and with a **name** in the
Cata/Mists UI code (`Blizzard_TalentUI/Cata/Blizzard_TalentUI.lua:673`). No Blizzard code
unpacks more than three values, so the return arity is not derivable from the UI source
(the API is C++).

| # | Source | Question | Why it matters |
|---|--------|----------|---------------|
| C1 | `SpellDocumentation.lua` per branch (~:190-197 / :416-424 / :375-383) + the classic global | (a) does the classic global accept a spell **name**? (b) how many values does it return, and is the id the 7th? | settles the name-vs-id rule per family (HU-6) |
| C2 | `tests/rogue_state.lua` | run it once | done by the orchestrator: **1095/0**, the unpack is correct |
| C3 | in-client (TBC/Wrath/SoD) | press the Consecration **icon** button while the prompt reads `next: cons` | confirms HIGH-1: expect `out of order: wanted cons, cast consecration` |
| C4 | in-client (Cata/Mists) | is the Seal of the Crusader button present in the paladin's panel? | confirms MEDIUM-2 |
| C5 | in-client (Cata/Mists) | are the shaman's common abilities offered? | confirms MEDIUM-1 (expected: no) |
| C6 | in-client (every family) | Forever: no Steady Shot slot; Cata/Mists: no `raptor` slot | confirms the family-scoped HUD id ownership |
| C7 | build gate | after **any** edit to `classes/paladin.lua` / `classes/warrior.lua`: `luac5.1 -p` them | the 201st file-scope local is a load failure, not a test failure |

## 7. Justified exceptions (documented, not defects)

1. **The hold branch precedes the neutral branch** (`practice.lua:3694-3707`) — HU-8: a
   neutral press during an explicit hold is an illegal cast, so the grading cannot be
   freed by spamming a heal through every hold. Pinned by `tests/practice_state.lua:2557-2578`.
2. **A family with no published neutral bucket answers `nil`** — the engine never guesses a
   neutral set for a client the class did not describe; the ability is simply not offered.
   (Residual: J-1.)
3. **The prepull tables are citations-only** where no drill consumes them (HU-12) — the
   `*_prepull` keys cannot collide with a combat-rotation key, and the file says so.
4. **`live` / `engine` as two independent axes**, with `engine = false` rows naming the
   exact read they wait for (HU-13) — a row the engine has no arm for must not enter the
   button vocabulary.

## 8. What the audit could not prove

Anything visual or temporal; anything secret-value dependent; the real spell ids on a client;
real client behaviour; whether the client serialises SavedVariables on `/reload` (it does
not — `TESTING.md` states it); whether a client is supported at all.
