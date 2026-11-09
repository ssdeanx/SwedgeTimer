# The grader seam: one spelling per spell (2026-10-20)

**Desk:** `grader-seam` · **Closes:** the final publish-gate deep audit's
**HIGH-1** (`bench/final_gate_audit_2026-10-20.md` §2) · **Scope:**
`practice_ui.lua`, `practice.lua`, `tests/practice_ui_state.lua`,
`tests/neutral_actions_state.lua` — nothing else · **Status:** landed, harness
green (43 steps / 0 failed, luacheck 2 warnings / 0 errors in 85 files).

## 1. The defect, in the audit's own words

> the scenario grader compares raw press keys while the classification and
> offer-gate layers normalise aliases → a correct press is graded F.

The paladin is the only class with two key spaces:

| the rotation / guide engine | the guide SLOTS |
|---|---|
| `cons` `exo` `hs` `am` (`classes/paladin.lua`'s `PRACTICE_ORDER_TWIST` and the FCFS orders) | `consecration` `exorcism` `holy_shock` `aura_mastery` (`classes/paladin.lua:3570-3593`) |

The class already normalises its OWN answer
(`classes/paladin.lua`'s `practice_filler_key`, `:5802-5818`: the engine's
filler kind `consecration` → the key `cons`), and the offer gate and the
closed-list suite both normalise through
`ST.<CLASS>.practice_canonical_key` (all six classes). The panel pushed **both**
vocabularies (`practice_ui.lua`'s `scenario_action_order`, the rotation leg and
the guide-slot leg), so the player got **two buttons for Consecration** — a bare
text `cons` and an icon `consecration` — and the grader compared the RAW press
with the RAW expectation: `actual == expected` failed → `out_of_order` → **F**,
streak broken, 0 XP, for the spell the prompt named.

## 2. The fix — both halves of the audit's prescription

### 2.1 One spelling per spell on the panel (the audit's option (a))

* `practice_ui.lua:4800` `scenario_action_order` — every key is canonicalised
  through the class's own alias table and the **canonical key is the button's
  key**; the dedupe is on the canonical key, so the rotation's `cons` and the
  guide slot's `consecration` are ONE button.
* `practice_ui.lua:4858` `scenario_action_spell_id` — the icon lookup goes
  through the same alias table: the canonical key (`cons`) finds the guide slot
  that spells it (`consecration`), so the one button carries the spell's icon
  (before, the icon rode the alias and the canonical button was bare text).
* The label is unchanged for the player: the rotation's own label when the
  rotation names a row (`Consecration`), otherwise the guide slot's own key
  (`holy_shock`) — the button reads as it always did, only its KEY is canonical.

The panel, before and after (the sandbox dump, the paladin on TBC):

```
before: cons | consecration | exo | exorcism | hs | holy_shock | am | aura_mastery | ...
after : cons[Consecration] ICON | exo[Exorcism] ICON | hs[holy_shock] ICON | am[aura_mastery] ICON | ...
```

### 2.2 The grader does not depend on the panel (the audit's option (b))

* `practice.lua:3626` `H.practice_canonical_key(class_key, key)` — the class
  contract seam, beside `H.practice_neutral_actions` (the same shape: a class
  key OR the class module; the identity is the fallback).
* `practice_ui.lua:647` `ui.canonical_key(key)` — the UI's seam over it. It is a
  **ui-table member, not a file-scope local**: `practice_ui.lua` sits at 199 of
  Lua 5.1's 200 file-scope locals, so a 200th would be a LOAD FAILURE on every
  client (the audit's HIGH-3). The module is still at 199 locals after the
  change (`luac5.1 -l practice_ui.lua` → `199 locals`).
* `practice_ui.lua:5129` `scenario_close_step` — the **caller** normalises the
  press (and, defensively, the class's answer) before the comparison. The
  ENGINE stays pure: `H.rotation_run_decide` still compares the two strings it
  is handed and knows nothing of the class's alias table.
  A press the class published as **neutral** keeps its own spelling — the
  neutral set is keyed on the class's own vocabulary and a neutral key is never
  an alias of a rotation action (the closed-list suite holds that).
* `practice_ui.lua:5483` `drill_list_grade` + `:5539` `drill_list_pick_press` —
  the **drill-list** path normalises the pick the same way, before the ctx is
  built, so every alias the class's grader reads (ctx.pick / ctx.pressed /
  ctx.action / ctx.last_action) carries the canonical key.

## 3. The pins (`tests/practice_ui_state.lua` §29, §29e)

The pins drive the REAL class modules (the same sandbox as section 27) and the
panel's own buttons. The class's own ANSWER is driven by the pin (the `want`
variable): what is under test is the panel ↔ grader seam, not the class's
decision (the rotation pins hold that).

| pin | claim |
|---|---|
| §29 (a) | the panel offers **ONE button per spell** — no two spellings of one spell |
| §29 (b) | the button that carries a spell's **icon is the canonical one** |
| §29 (c) | the press of the panel's **own button** for the action the prompt names grades **CORRECT** (never `out_of_order`) — for every class and every slice the table names |
| §29 (d) | a press in **ANY spelling the class knows** grades CORRECT too (`consec`, `consecration`, `exorcism`, `aura_mastery`, `command`, `blood`, `hammer_of_wrath`, …) |
| §29e | the **drill-list** path normalises the pick the same way |

The walk (`PRACTICE_CLASS_SPECS` + the new `GRADER_SPECS`): the paladin on
**TBC** (project 5) and on **Forever** (project 18) — the families the audit
named — with its four filler rows (`cons` / `exo` / `hs` / `am`) walked
explicitly; the warrior on Forever, and the druid, rogue, shaman and hunter on
Era. Each class's own published rotation slice is walked action by action.

**The closed-list suite follows the panel** (`tests/neutral_actions_state.lua`):
`guide_slot_keys` now returns the **canonical** slot keys (the shipped action
row canonicalises the guide slots), so the vocabulary the closed list classifies
is the vocabulary the player sees. The paladin's ten expected mis-pick lists
moved with it — the four renamed spellings (`aura_mastery` → `am`,
`consecration` → `cons`, `exorcism` → `exo`, `holy_shock` → `hs`) and nothing
else: the CLASSIFICATION of every key is unchanged (the classification reads
`slice_keys[norm(key)]`, and the canonical key normalises to itself).

### 3.1 A crossfire landed mid-flight (recorded, not hidden)

While this lane was proving its mutants, the `paladin-scenario` lane landed the
audit's **MEDIUM-2** fix in `classes/paladin.lua` (outside this lane's scope):
the paladin's neutral publish became **family-scoped** with ERA / TBC / WRATH /
FOREVER / CATA / MISTS / **RETAIL** buckets, and the Cata / Mists / Retail
buckets carry **no `sotc`** (the Seal of the Crusader was removed in 4.0). That
change moved the closed-list suite's expectations, and the suite is THIS lane's
file, so the three affected slices were re-pinned against the tree:

* the Cata and the Mists slices lost `sotc` from the expected neutral set and
  gained it in the expected mis-pick list (the shared sim's grid still offers
  the key there, and it can only ever be a mis-pick);
* `FAMILY_PROJECT` learned the `RETAIL` token (the mainline client, project 1)
  — the suite's "every family bucket is a known family" check demands it;
* a **RETAIL slice** was added (the retail client plays no rotation, exactly
  like the Cata and the Mists clients), so the new bucket is walked and not
  merely named.

The other five classes' expectations did not move.


## 4. The mutation proofs (`/tmp/opencode` copies; the repo tree was never mutated)

| mutant | killed by | full harness on the mutant |
|---|---|---|
| **M1** the panel canonicalisation removed (`scenario_action_order` pushes the raw keys, `scenario_action_spell_id` looks the raw key up) | 6 checks fail: `PALADIN@5`/`PALADIN@18` — "the panel offers ONE button per spell (**twice: cons, exo**)" + "the cons button carries the consecration icon" + "the exo button carries the exorcism icon" | 43 steps, **1 failed** (only `practice_ui_state.lua`) |
| **M2** the grader's normalisation removed (the scenario seam compares the raw strings again) | 114 checks fail: every alias press of the paladin reads "the press grades CORRECT (got 0, want 1)" / "the press is not a mis-pick (got 1, want 0)" / "the popup reads CORRECT (got OUT OF ORDER, want CORRECT)" | 43 steps, **1 failed** (only `practice_ui_state.lua`) |
| **M3** the drill-list normalisation removed | 5 checks fail: "the pick rides in ctx.pick / ctx.pressed / ctx.action / ctx.last_action as the canonical key (got consecration, want cons)" + "the session's pick is the canonical key" | 43 steps, **1 failed** (only `practice_ui_state.lua`) |

M1 is the audit's defect reproduced exactly: the panel offered Cons twice, and
the icon rode the alias. M2 is the audit's other half: with the panel fixed,
the ONLY thing that can catch a grader that does not normalise is a press in a
non-canonical spelling — the panel's own button can no longer do it, because
after the canonicalisation the button's key IS the canonical key.

## 5. The verification

* **Harness:** `bash tests/run.sh` → **43 steps, 0 failed**.
* **luacheck:** **2 warnings / 0 errors in 85 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The four touched files
  are **0/0** on their own.
* **Suites:** `tests/practice_ui_state.lua` **2455 checks** (was 1760; +695 from
  §29/§29e), `tests/neutral_actions_state.lua` **7023 checks** (was 6224; +799
  from the new Retail slice, +0 from the canonicalisation — the model follows
  the panel without adding a check).
* **The local ceiling:** `luac5.1 -l practice_ui.lua` → **199 locals** (the
  audit's HIGH-3 headroom is intact — the new seam is a ui-table member).
* **Line endings:** `practice.lua` and `practice_ui.lua` are CRLF and stay CRLF
  (every line, including the new ones); the two test files are LF and stay LF.
* **The repo tree was never mutated:** every mutant was proved on a
  `/tmp/opencode/mut_grader*` copy of the tree (Media/ and docs/ symlinked so
  the whole harness could run).

## 6. UNCONFIRMED / not proven here

* **In-client:** nothing here is proven in a client. The panel's buttons, the
  icons and the grades are offline-proven only; the operator's in-client pass
  remains the only way to confirm the real client's spell data and the real
  panel's look.
* **The button label of a guide-only action** is the class's own spelling of
  the spell (`holy_shock`, `aura_mastery`) on the families whose rotation
  names no row for it — the same text the button carried before the change;
  on the families whose rotation DOES name the row (SOD) the rotation's own
  label reads `Holy Shock`. No display regression; the label was not part of
  the audit's finding.
* **The other five classes** carry one key space (no alias table), so the
  canonicalisation is the identity for them and their panels are byte-identical
  before and after. The pins still walk them (the seam is theirs too).
* **HIGH-2** (the "client's own rank art" claim) and **HIGH-3** (the local
  ceiling) are other findings of the same audit and are NOT closed here.
