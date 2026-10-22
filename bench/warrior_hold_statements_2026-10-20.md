# bench/warrior_hold_statements_2026-10-20.md — the warrior's half of HU-8 + the sunder default

Desk: `warrior-hold`. Date: 2026-10-20. Validation owner: **orchestrator**.

Two items the last wave filed:

1. the warrior's **hold statements** (the class-side half of HU-8 — the other five
   classes are done, see `bench/class_hold_statements_2026-10-20.md`);
2. the **`hud_show_sunder` default** (operator ruling: the new mirror ships, the
   HUD row does not change for a fresh profile).

Files changed (this lane's scope):

| file | what changed |
|---|---|
| `classes/warrior.lua` | `ST.WARRIOR.practice_scenario_step` now states the guide's hold (`:3926`); the stale header comment above the practice block re-cut |
| `config_presets.lua` | `hud_show_sunder = true` → `false` (`:1303`) + the comment rewritten |
| `tests/warrior_state.lua` | the stale "a HOLD verdict answers nil" pin re-cut (`:4329`); the new section 37 (`:4632`) with the hold statements, the unknown and the three states through the engine |
| `tests/hud_state.lua` | the sunder-default pin (`:1215`) — out of the "ships true" list, into the "ships false" shape |
| `tests/options_load_state.lua` | the sunder-default pin (`:608`) — the per-class `off_slots` list + the branch in the (a2) default loop |
| `tests/hud_templates_state.lua` | the sunder-default pin (`:81`) — the suite's own `ship_false` list (see §6: the scope list named two sunder pin files; a third exists) |

Nothing else was touched. No git write, no lint-config change, no TOC / version /
docs / changelog edit. `practice.lua`, `practice_ui.lua`, `option_tables.lua`,
`hud.lua`, `bars.lua`, `main.lua`, `diag.lua`, `compat.lua`, `run.sh` and the other
classes are untouched.

---

## 1. The contract the class codes against (read from the landed engine)

`practice.lua`'s accessor (`H.practice_scenario_step`, `practice.lua:3450`):

```lua
if type(action) ~= "string" or action == "" then
    -- No action: the only non-unknown answer left is an explicit hold.
    if result.hold == true then
        return { action = nil, hold = true, reason = reason }
    end
    return nil
end
-- An action was named: this is a decision to cast, whatever the hold flag says.
return { action = action, reason = reason }
```

* a **hold statement** is a decision: casting during it is an illegal cast (F);
  doing nothing is correct and records **no attempt** (no points);
* a step with **neither an action nor a hold** stays UNKNOWN (no attempt, never a
  wrong grade);
* a step that names an **action** is an action (the hold flag is ignored).

## 2. The warrior's step, before and after

Before (`classes/warrior.lua`): the step took only the FIRST return value of
`practice.expected(self, ctx)` (the action) and dropped the guide's verdict table:

```lua
local action = practice.expected(self, ctx)
if action == nil then
    return nil
end
```

So every hold verdict (no action) read UNKNOWN.

After: the step asks the guide's own verdict, and the three outcomes are the same
three the engine knows:

```lua
local action, out = practice.expected(self, ctx)
if type(out) ~= "table" then
    return nil                                   -- unknown: no verdict at all
end
if type(action) == "string" and action ~= "" then
    ... return { action = action, reason = reason or action }   -- an action
end
if out.hold == true then
    ... return { action = nil, hold = true, reason = reason }  -- an explicit hold
end
return nil                                       -- unknown: a state it cannot read
```

The **reason is the guide's own text** (`out.hold_text` — "RIDE" / "HOLD"), never a
re-decided one; the fallback "HOLD" only fires when the guide's caption is missing
or empty (the hunter's shape, `classes/hunter.lua:3624`).

## 3. The guide's three hold verdicts, and what the step states

The warrior's guide (`warrior_guide.lua`) has three hold verdicts:

| verdict | source | the guide's verdict | the step states |
|---|---|---|---|
| **RIDE** | `warrior_guide.lua:1303` (base) / `:1346` (branch path) — `hs_queued` / `cleave_queued` | `action = nil, hold = true, hold_text = "RIDE"` | `{ action = nil, hold = true, reason = "RIDE" }` — an explicit hold |
| **HOLD** | `warrior_guide.lua:1399` — the filler's rage shortfall | `action = nil, hold = true, hold_text = "HOLD"` | `{ action = nil, hold = true, reason = "HOLD" }` — an explicit hold |
| **CANCEL** | `warrior_guide.lua:1286` — the TBC HS-cancel cue (a queued spend the Execute press kills) | `action = "execute", hold = true, hold_text = "CANCEL"` | `{ action = "execute", reason = "Execute below 20 %" }` — **an action** |

### Why CANCEL stays an action (the one judgement call in this lane)

The brief's own rule settles it: *"A step that names an action stays an action."*
The guide's CANCEL verdict **names an action** — `action = "execute"` — and the
guide's own header says the CANCEL cue replaces the rule-4 RIDE ("the prompt
carries hold = true, hold_text = "CANCEL" … instead of the rule-4 RIDE",
`warrior_guide.lua:277-280`). The live guide lights the **Execute** icon and paints
"CANCEL" as the overlay caption; the rotation text reads the action, not the caption
(`ST.WARRIOR.get_rotation_key`, `classes/warrior.lua:3577-3582`: the action wins,
the hold text is only the fallback when there is no action).

So a CANCEL step that answered "hold" would teach the **opposite** of the live
guide: the player is told "press nothing" while the guide shows the Execute lit,
and the correct press would be graded as an illegal cast. The class's own invariant
is explicit about this: *"The engine's pick for this context: the same path the
live guide uses, so the practice pick and the live pick can never disagree"*
(`classes/warrior.lua:3831-3832`).

The guide suite already pins the CANCEL verdict's shape:
`tests/warrior_guide_state.lua:741-747` — `out.action == "execute"`,
`out.hold == true`, `out.hold_text == "CANCEL"`.

**The cue itself never reaches the practice path** (it is a live-gather reading:
`classes/warrior.lua:2929` arms it on TBC only, and the class's practice input
builder does not forward it), so the practice path never produces a CANCEL verdict
today. The step's rule covers it by construction — an action wins — and no input
was added for it (a dead input would be unpinnable: the step's answer is the same
either way, because the verdict names the Execute).

**If the operator rules that CANCEL must be a hold statement**, the change is one
line in `classes/warrior.lua` (return the hold statement when `out.hold == true`
even when an action is named) — but it would then contradict the live guide's lit
Execute icon, so it needs the operator's word, not this lane's.

## 4. The sunder mirror default (operator ruling)

`config_presets.lua` shipped `hud_show_sunder = true`, which put a **new visible
icon** in the warrior's TBC HUD row without a gate. The ruling: the mirror ships
(one click to enable) and the row is unchanged for a fresh profile.

* `hud_show_sunder = false` (`config_presets.lua:1303`).
* The **gate needs no change**: the provider already hides the mirror unless the
  key reads exactly `true` (`classes/warrior.lua:3465-3474`: `nil = off`, the druid
  Claw shape) — so `false` and `nil` both hide, and the option toggle still turns
  it on.
* The **W-T2 template** still turns it on on an explicit pick
  (`config_presets.lua:1375`: `sunder = true` in `full_trinkets`) — the templates
  are untouched.
* The comment above the key was rewritten: the old one claimed "the HUD master
  stays off" (stale — `hud_enabled` ships true) and "TBC guide-only until the HUD
  lane mirrors it there" (stale — the TBC mirror landed, `classes/warrior.lua:3291-3293`).

No other default moved; the rest of the union still ships true.

## 5. The pins

`tests/warrior_state.lua` §37 (`:4632`) — the new section:

* the **RIDE** verdict states an explicit hold, names no action, and carries the
  guide's own caption ("RIDE");
* the **HOLD** verdict states an explicit hold, names no action, and carries the
  guide's own caption ("HOLD");
* an **unreadable state** stays unknown (no hold statement);
* the **three states through the engine's own decision**
  (`H.practice_scenario_step` → `H.rotation_run_decide`):
  * a cast during the hold → `illegal_cast` (F, an attempt, a mis-pick);
  * nothing during the hold → `hold_ok` (correct, no attempt, no points);
  * an unknown step → `unknown` (no attempt, never a mis-pick).

`tests/warrior_state.lua` §34 (`:4329`) — the **stale pin re-cut, not deleted**:
the old "a HOLD verdict answers nil (the engine grades it unknown)" now asserts the
hold statement (the class's decision became explicit).

The sunder-default pins: `tests/hud_state.lua:1215`, `tests/options_load_state.lua:608`
and `tests/hud_templates_state.lua:81` — each now asserts the mirror **ships false**
and **ships no true default** (the druid-Claw shape), in the shape that suite
already had for the druid's Claw and the rogue's kidney/restealth/bandage mirrors.

## 6. A third sunder-default pin file (the scope list missed it)

The brief named `tests/options_load_state.lua` and `tests/hud_state.lua` as the
sunder-default pin files. The harness proved a **third** one:
`tests/hud_templates_state.lua` pins "hud_show_<key> ships true" for every slot of
every class (its §2), so the ruling turned it red (`FAIL Warrior: hud_show_sunder
ships true in the defaults`). The pin was re-cut mechanically with the suite's own
`ship_false` mechanism (the shape the druid's Claw mirror already uses there:
`ship_false = { claw = true }`). The file is a **test** file of the same pin
category the brief ordered; the "out of scope" list does not name it. Flagged here
so the orchestrator can see the one file outside the enumerated scope.

## 7. Mutation proofs — 10 of 10 killed

Disposable copy: `/tmp/opencode/warrior-hold-mut` (the repo tree is never touched).
Script: `/tmp/opencode/warrior_hold_mutations.py`.

| # | mutation | killed by |
|---|---|---|
| M1 | the warrior's hold degrades to unknown (the step answers nil) | `warrior_state` |
| M2 | the warrior INVENTS a hold (an unknown becomes a hold) | `warrior_state` |
| M3 | the hold's reason is re-decided, not the guide's own text | `warrior_state` |
| M4 | the hold statement names an action (the engine reads an action and drops the hold) | `warrior_state` |
| M5 | a named action no longer names an action | `warrior_state` |
| M6 | the sunder default flips back to true | `hud_state` |
| M7 | the sunder default flips back to true | `options_load_state` |
| M8 | the sunder default flips back to true | `hud_templates_state` |
| M9 | the sunder default is removed instead of shipped false (nil = off) | `hud_state` |
| M10 | the sunder default is removed instead of shipped false (nil = off) | `options_load_state` |

## 8. Verification

* `bash tests/run.sh` → **41 steps, 0 failed**.
* luacheck → **2 warnings / 0 errors** (the shipped floor: `compat.lua:36`,
  `main.lua:81` — this lane adds none).
* Suites this lane owns: `warrior_state` 1204 (was 1182: +22), `hud_state` 683
  (was 682: +1), `options_load_state` 3432, `hud_templates_state` 900.
* Line endings preserved: `classes/warrior.lua` stays CRLF (4201 lines, 4201 CR);
  `config_presets.lua` and every test file stay LF. No trailing whitespace on any
  touched line (in fact: none in any of the six files).
* The only files with a new mtime are the six listed above.

**Not verified in-client.** The two proofs this lane holds are "verified offline"
(mutation-proofed on a disposable copy). The in-client behaviour (the practice
panel's hold prompt, the TBC HUD row without the Sunder icon) needs a client.
