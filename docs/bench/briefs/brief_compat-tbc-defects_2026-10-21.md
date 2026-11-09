# Brief: compat TBC defects (2026-10-21) — the protected call and the name/id crash

**Operator in-client report, 2026-10-21 (TBC Anniversary, HUNTER):**
1. `1x [ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the protected function
   'check_interact_distance()'` — stack: `compat.lua:954` <- `hunter_ui.lua:877
   update_range_helper` <- `hunter_ui.lua:1510 update` <- `hunter_ui.lua:1539
   on_bar_update` <- `classes/hunter.lua:909` <- `guard.lua:178 run` <- `bars.lua:693`.
2. `1x ...Deprecated_SpellBook.lua:19: bad argument #1 to 'IsSpellInSpellBook'
   (outside of expected range ...)` — stack: `compat.lua:236 is_spell_known_state` <-
   `compat.lua:250 is_spell_known` <- `classes/hunter.lua:2276 resolve_known` <-
   `classes/hunter.lua:2281 resolve_guide_icons` <- `classes/hunter.lua:824 post_init` <-
   `main.lua:830 post_init` <- `main.lua:712 init_libs`. Locals: `spellID="Kill Shot"`.

This lane owns BOTH compat-side defects. A second lane (dispatched the same wave) owns the
range-engine consumers (`main.lua` `rf_update`, `hunter_ui.lua`, the vendored
LibRangeCheck) — do NOT touch those files.

## Defect 1 — `api.CheckInteractDistance` calls a protected function

`compat.lua:950-965` does `local check_interact_distance = rawget(_G,
"CheckInteractDistance")` and calls it. On TBC Anniversary 2.5.x the client has that
global **in its protected-function registry**: every call raises ADDON_ACTION_BLOCKED.
Worse, the call is per frame, so it takes the whole hunter class hook down through
`guard.run`'s 25-throw quarantine.

This was the *replacement* for the earlier blocked `IsItemInRange` path — i.e. the range
fix moved from one protected call to another. The standing operator policy is **zero
client range calls**: no protected distance/range function may be called on ANY family.

Required:
- Remove `api.CheckInteractDistance` and the `rawget` entirely (a nil-returning stub
  would hide the reason). Keep `api.UnitDistance` (exact yards, already pcall-wrapped,
  already probed per family) — that is the only distance source.
- `compat.lua` must contain no reference to `CheckInteractDistance` afterwards, in code or
  in a comment that implies it is usable (update the comment block at 943-949 to record
  WHY: TBC Anniversary protects it; operator in-client evidence 2026-10-21).
- The consuming call site in `hunter_ui.lua` is the OTHER lane's job — do not edit it.
  Coordinate only through this brief: `api.CheckInteractDistance` ceases to exist.

## Defect 2 — `api.is_spell_known` throws on a spell NAME

`classes/hunter.lua:2276` passes `spell_token(id)`, which on TBC is the spell NAME
("Kill Shot") — by design, because old clients' `IsSpellKnown` took a name. But on this
client the global `IsSpellKnown` is Blizzard's **deprecated shim**
(`Blizzard_DeprecatedSpellBook`), which forwards to
`C_SpellBook.IsSpellInSpellBook(spellID, ...)` — numeric ID only. A string throws, and the
throw escapes `api.is_spell_known_state` (no pcall), killing the caller's `post_init`.

Required:
- `api.is_spell_known_state(spell_id)` must NEVER throw, for ANY input type:
  - accept a number (an id) or a string (a name);
  - for a string, resolve it to a numeric id through the compat spell-info path
    (`GetSpellInfo` / `C_Spell.GetSpellInfo` — use the wrapper compat already has; do not
    add a second resolution path);
  - call EVERY probe under `pcall` and treat a throwing probe as "no answer" (continue to
    the next probe), never as a fatal error;
  - a token that resolves to nothing returns `false, "unknown"` — never a guess, never a
    throw;
  - the probe ORDER must not change for clients where the existing chain answers (the
    classic clients keep the same answer source).
- `api.is_spell_known(spell_id)` keeps its contract: `true`/`false`, never nil, never a
  throw.
- Document in the function's comment that the TBC deprecated shim is id-only and that a
  name is resolved first (with the in-client evidence date).

## Proof required (this is an offline-proof shop; the operator asked for tests, not probes)

A NEW suite `tests/spell_known_state.lua` that models the failing client in a sandbox:
- `IsSpellKnown` = a function that mirrors the deprecated shim: it forwards its argument to
  `C_SpellBook.IsSpellInSpellBook` and that function THROWS unless the argument is a
  number in range (reproduce the client message shape);
- `C_SpellBook.IsSpellKnown` / `IsSpellKnownOrInSpellBook` present (the modern probes);
- `GetSpellInfo` resolving a known name to an id, and answering nil for an unknown name.

It must pin:
1. `api.is_spell_known("Kill Shot")` does NOT throw; with GetSpellInfo resolving the name
   the probe is called with the NUMERIC id and the answer comes back (true/false
   accordingly).
2. `api.is_spell_known("No Such Spell")` returns false and `is_spell_known_state` returns
   `false, "unknown"` — no throw, no guess.
3. `api.is_spell_known(<number>)` still probes with that number (no behaviour change for
   the clients where ids are the token).
4. A probe that throws is skipped and the next probe answers — the caller never sees a
   throw.
5. `compat.lua` contains no `CheckInteractDistance` (a static scan in the suite, so the
   removal cannot regress).

Also: `bash tests/run.sh` green + exact numbers, `luacheck` at the standing floor
(2 warnings / 0 errors), and MUTATION PROOFS on a `/tmp/opencode` copy (never the working
tree) for every new guard — remove the guard, the suite must fail. The orchestrator adds
the `tests/run.sh` line (FILE it, do not edit run.sh).

## Scope / write permission
- YOU OWN: `compat.lua`, `tests/spell_known_state.lua` (new).
- YOU MUST NOT edit: `main.lua`, `hunter_ui.lua`, `Libs/**`, `classes/**`,
  `tests/run.sh`, any other test — the parallel lane owns those. If you believe one must
  change, FILE it with file:line and the reason.
- **Context discipline:** do not read whole files. `compat.lua` is large — use targeted
  greps and small `sed -n` reads. Do not cat it end to end.
- No git. No lint-config changes. Preserve file endings (compat.lua is CRLF — keep it
  CRLF). Warnings traced, never silenced with `_`. No new protected/secure calls.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (desk journal + `bench/lessons.md` + the bench, journals before artifacts) ->
`desk-open desks/compat-tbc-defects/` -> `desk-journal` -> `signal-write`.

## Deliverable
`bench/compat_tbc_defects_2026-10-21.md` (confirm absent before writing): the two defects
with the client evidence, what changed, the suite numbers, the mutation list, the run.sh
line you filed, and every UNCONFIRMED item. Plus your desk journal and a done signal.

## Validation owner
The orchestrator (re-runs the harness, re-reads the diff, hands the operator the copy
list).
