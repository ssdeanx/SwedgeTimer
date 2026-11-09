# Brief: range-lrc-guard (2026-10-21) — the range-checker fix

## Objective
Stop the addon from calling a client-BLOCKED API from the vendored range checker, and
restore a working melee/ranged ladder on every supported client family.

## Why (operator in-client evidence, Classic Era 1.15.9, 2026-10-21)
```
[ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the protected function 'UNKNOWN()'.
[LibRangeCheck-2.0.lua]:498: in function <...:497>
[SwedgeTimer/main.lua]:1797: in function <SwedgeTimer/main.lua:1790>
```
- `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua:498` is
  `return IsItemInRange(item, unit)` (the item checker).
- The lib resolves the global at line 422:
  `local IsItemInRange = (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange`.
- On `classic_era` the legacy global IS the modern C function:
  `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29`
  -> `IsItemInRange = C_Item.IsItemInRange;` (same on `classic_anniversary`,
  `classic_titan`; on `origin/live` and `origin/forever` the legacy global is absent
  but the lib still resolves `C_Item.IsItemInRange`).
- The modern API takes an ItemInfo, not the legacy item id — so the legacy call shape is
  invalid on those clients as well.
- The block is NOT a catchable Lua error (the client blocks the action), so the addon's
  `pcall` in `main.lua` (the dead-man retry at ~1790) cannot suppress it.
- The call site in the addon: `main.lua:1797` — `self.ranged_range_checker_func` was
  resolved from `LRC:GetHarmMaxChecker(r)` (r = 30, or 35 for a hunter) at
  `main.lua:1774-1775`. On the operator's client that selected the ITEM checker.

## Already established (orchestrator; do not re-derive)
- NO legacy `IsSpellInRange` global is defined on ANY of the five target branches
  (`classic_era`, `classic_anniversary`, `classic_titan`, `origin/live`,
  `origin/forever`). Only `C_Spell.IsSpellInRange(spellIdentifier, targetUnit)` exists
  (true/false/nil), plus `C_SpellBook.IsSpellBookItemInRange(index, spellBank)` on
  live/forever (`Interface/AddOns/Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua:47`).
  => the lib's spell checkers (which capture the legacy global at load, line 421) always
  answer "unknown" on every supported client; their `type(IsSpellInRange) ~= "function"`
  guard is what stops them.
- `CheckInteractDistance` EXISTS on all five branches and is CALLABLE from addon code on
  the operator's client: the melee checker (`LRC:GetHarmMinChecker(2)` -> the interact-3
  band, 8 yards) ran at `main.lua:1791` WITHOUT a block, immediately before the blocked
  call at `main.lua:1797`.
- The interact bands in the lib: `DefaultInteractList = { [3] = 8, [4] = 28 }`, with
  race overrides (Tauren {3]=6,[4]=25}, Scourge {3]=7,[4]=27).

## The contract
R1. **Never call the item-range API on a client where the modern `C_Item.IsItemInRange`
    exists.** The item checkers must not be added to a checker list there, and
    `lib:init`'s item-based `minRangeCheck` must not be built from `HarmItems[15]`.
    On a client that still has the LEGACY `IsItemInRange` global and no `C_Item`
    replacement, the legacy behaviour must be unchanged.
R2. **The ladder must still answer on a client whose spell-range API cannot answer.**
    When the legacy `IsSpellInRange` global is absent, the spell checkers can never
    answer, so the checker lists must fall back to the interact-distance checkers
    (melee band 8 yd, ranged band 28 yd) INSTEAD of a list of checkers that all answer
    "unknown". The addon reads:
      - `LRC:GetHarmMinChecker(2)`  -> the melee checker (must answer true/false),
      - `LRC:GetHarmMaxChecker(30)` / `(35)` -> the ranged checker (must answer true/false),
      - `LRC:GetRange("target")` -> min/max range numbers for the out-of-range bar.
    All three must keep their current signatures and answer shapes.
R3. **[DEFERRED — the operator declined the in-client probe on 2026-10-21: "i have to copy
    all files over. so use a test, like we always do."]** The modern
    `C_Spell.IsSpellInRange` therefore stays UNUSED in this lane: whether the client
    blocks it is not decidable offline, and a wrong guess means a second ADDON_ACTION_BLOCKED
    spam loop. SHIP R1+R2 ONLY. Do not add the C_ path, do not add a feature flag for it,
    and do not leave a dead branch for it — an honest coarse ladder beats a gamble.
    Record in your report that the accurate per-class range (the C_ path) is an OPEN
    follow-up that needs one in-client confirmation, and state exactly which command the
    operator would have to run for it.
R4. **Audit the whole lib for other blocked calls** on the modern clients (the lib also
    calls `GetItemInfo`, `GetSpellInfo`, `GetInventoryItemLink`, `UnitClass`, `UnitRace`,
    `CheckInteractDistance`, `IsSpellInRange`). List every client API the lib calls and
    mark each one: legacy-only / modern / UNCONFIRMED, with the client source line you
    verified it on.
R5. **No behaviour change on a legacy client.** A profile that HAS the legacy globals
    must behave exactly as before (same checkers, same answers, same order).
R6. **No change outside the range path.** `main.lua`, `compat.lua`, the bars and the
    options are NOT yours to edit. If the fix needs a change outside the lib, FILE it on
    the bench with file:line and the reason — do not edit it.

## Scope / write permission
- YOU OWN: `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`
  and `tests/lrc_guard_state.lua`.
- YOU MUST NOT edit: `main.lua`, `compat.lua`, any other `Libs/` file, the TOCs,
  `tests/run.sh`, any other suite. File what you need elsewhere.
- No git. No lint-config changes. Preserve line endings. Warnings: trace them, never
  silence with `_`.
- The vendored lib ALREADY carries local patches (the `IsSpellInRange` type guards at
  ~457-462, the `C_Item` resolution at 422, the secret-value checks). Keep the new patch
  in the same style: minimal, dated, with a comment that says WHY in client terms, and
  record the upstream situation in your bench report. Do not reformat the file.

## Tests (your own proof)
- Extend `tests/lrc_guard_state.lua` (the suite that already pins the LRC guards):
  - static pins for the new guards (exact counts, so a guard cannot silently vanish);
  - an EXECUTION test under a MODERN-client profile (`C_Item.IsItemInRange` present, no
    legacy `IsSpellInRange`, `CheckInteractDistance` present) proving: (a) the item
    checker is never called — install a spy that FAILS the test if it is called;
    (b) the harm min/max checkers answer from the interact bands; (c) `GetRange` answers
    numbers instead of raising;
  - an EXECUTION test under a LEGACY profile (legacy globals present) proving the
    behaviour is unchanged (same checkers, same answers).
- MUTATION PROOFS on a `/tmp/opencode` COPY (never the working tree) for every new
  guard: remove the guard -> the suite must fail. Copy the tree WITHOUT `Media/`,
  `docs/` and `.git` (Media is 187 MB and fills the tmpfs).
- Run `lua5.1 tests/lrc_guard_state.lua` and then `bash tests/run.sh`; report the exact
  numbers. An unrelated red from another lane's in-flight work is CROSSFIRE — report it,
  do not fix it.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (your desk journal + `bench/lessons.md` + the bench, journals before
artifacts) -> `desk-open` `desks/range-lrc-guard/` -> `desk-journal` (append what you
did, current state, next step) -> `signal-write` (done/checkpoint/hands-up JSON into
`desks/range-lrc-guard/.signals/`).

## Operator facts (2026-10-21)
- The operator plays ROGUE on Classic Era; the class must not matter (the fix is
  client-wide, not class-specific).
- The operator copies the addon files to the client by hand for each test — the
  orchestrator deploys the changed files to the client folder after the lane lands, so
  nothing in your scope depends on the client copy.

## Deliverable
Bench file `bench/range_lrc_guard_2026-10-21.md` (confirm absent before writing):
what changed (file:line), the before/after checker behaviour per client profile, the
R3 probe result you were given, the test numbers, the mutation list, the R4 API audit
table, and every UNCONFIRMED item. This is an OFFLINE proof only — in-client
confirmation is owed by the operator and must be stated as such.

## Validation owner
The orchestrator: it re-runs the suite, re-reads the diff, and asks the operator for the
in-client confirmation on Classic Era.
