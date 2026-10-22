# compat TBC defects — protected distance call + spell-name throw (2026-10-21)

**Lane:** `compat-tbc-defects` (desk `desks/compat-tbc-defects/`)
**Owner files:** `compat.lua`, NEW `tests/spell_known_state.lua`
**Status:** both defects fixed and mutation-proven offline. In-client confirmation OWED (see
UNCONFIRMED). The harness is red only on files this lane does not own, plus one test file that
pins the removed wrapper (fix filed below).

## 1. Operator in-client evidence (TBC Anniversary, HUNTER)

1. `1x [ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the protected function
   'check_interact_distance()'` — stack `compat.lua:954` <- `hunter_ui.lua:877
   update_range_helper` <- ... <- `bars.lua:693`. Per-frame call, so it quarantined the whole
   hunter class hook through `guard.run`.
2. `1x ...Deprecated_SpellBook.lua:19: bad argument #1 to 'IsSpellInSpellBook' (outside of
   expected range ...)` — stack `compat.lua:236 is_spell_known_state` <- `compat.lua:250
   is_spell_known` <- `classes/hunter.lua:2276 resolve_known`; local `spellID="Kill Shot"`.

## 2. What changed

### Defect 1 — `api.CheckInteractDistance` removed

`compat.lua:988-1007` (comment) and the section that followed:

- `api.CheckInteractDistance` and the `rawget(_G, "CheckInteractDistance")` are GONE. No stub:
  a nil-returning stub would hide why the call is gone.
- The comment records the protected-function status, the `ADDON_ACTION_BLOCKED` failure shape,
  the operator date 2026-10-21, and `api.UnitDistance` as the only distance source.
- `grep -n "CheckInteractDistance\|check_interact" compat.lua` returns no match (exit 1). The
  comment cites Blizzard's call site by path:line, so the literal identifier stays out of the
  file and the suite's strict scan keeps its teeth.
- The consuming call site was the other lane's file: `hunter_ui.lua:877`. The parallel lane has
  since replaced it with `api.UnitDistance("target")` (live `hunter_ui.lua:891` at 18:08). This
  lane did not edit `hunter_ui.lua`.

**Citations (orchestrator-provided, wow-ui-source branch `classic_anniversary` — used as given,
not re-verified):**

- `Interface/AddOns/Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua:194` — the only Blizzard
  caller of `CheckInteractDistance`, and it is secure popup code. The addon block is
  runtime/client-side (the operator's `ADDON_ACTION_BLOCKED`), NOT documented.
- `Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua:101` — lists the function
  with no protection marker, which is why the in-client log (not the doc) is the authority for
  the protection.
- `Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1069` — calls
  `UnitDistanceSquared(frame.displayedUnit)` from ordinary insecure unit-frame Lua and trusts it
  only when `checkedDistance` is true. That is the addon-callable source; `api.UnitDistance`
  (`compat.lua:1009-1039`) normalises it to exact yards and returns nil for
  unchecked/secret/throwing readings.

### Defect 2 — spell knowledge never throws on a name

`compat.lua:229-297`:

- `spell_known_name_id(spell_name)` (241-250): strings only — a number is never "resolved".
  Exactly one resolution path, the existing `api.GetSpellInfo`, pcall-wrapped; the id is the 7th
  return; a secret or non-number id is nil. No second spell-info path was added.
- `api.is_spell_known_state(spell_id)` (261-292):
  - a non-(number|string) token returns `false, "unknown"` before any client call;
  - every probe call is `pcall`-wrapped (`pcall(probe, spell_id)`);
  - the token is probed AS GIVEN first;
  - on the first THROW only, the name is resolved once for the whole chain; that same probe is
    retried with the id;
  - a probe answer that is secret is "no answer", never compared;
  - `true, "known"` / `false, "not_known"` / `false, "unknown"`.
- `api.is_spell_known` (294-297) keeps the boolean contract: true/false, never nil, never throw.
- The section comment (229-240) names the TBC deprecated shim, records that it is id-only, the
  operator evidence date, and the lazy rule.

### Deliberate deviation: LAZY name→id, not eager

The brief says "for a string, resolve it to a numeric id". Implemented literally (resolve before
probing), that CHANGES the answer source on the classic clients whose `IsSpellKnown` takes a
name: 7 existing suites went red on the eager build:

- `shaman_state`: "utility: TBC feeds the Frost Shock cooldown (got nil, want 10)"
- `warrior_state`: "name-vs-id TBC: the rune probe is the resolved name"
- `hunter_state`: "TBC: the Viper name reads known" / "the knowledge probe ran by name"
- `rogue_state`: "unlearned Mutilate reads nil (got true, want nil)"
- `paladin_state`: 5 name-vs-id pins
- `bars_state`: 11 hunter range / rapid fire / aspect checks
- `hud_state`: 6 CS cooldown checks

The lazy design keeps the brief's own compatibility rule ("the classic clients keep the same
answer source"): the caller's token is probed first; only a THROWING probe resolves and retries
with the id. On TBC Anniversary the deprecated shim throws on a name, so the resolution happens
exactly where the client needs it. The same 7 suites are green on the shipped code (numbers in
§4).

## 3. New suite `tests/spell_known_state.lua` (251 checks, 0 failures)

Sandbox models TBC Anniversary 2.5.x over the REAL `compat.lua` (`loadfile` + `setfenv`; no copy
of the code under test):

- `IsSpellKnown` forwards to `C_SpellBook.IsSpellInSpellBook`, which records the argument and
  throws unless it is a numeric id in 1..1,000,000 (the operator's message shape).
- `C_SpellBook.IsSpellKnown` / `IsSpellKnownOrInSpellBook` present and id-only.
- `GetSpellInfo` resolves a known name to an id and answers nil for an unknown name; classic
  7-return shape.
- Secret sentinels keep their numeric type so only the `is_secret` guard can stop them.

Pins: TBC name resolves and answers (true and false cases); unknown name is `false, "unknown"`
with no id retry and one resolution; a numeric token is probed with exactly that number and is
never resolved (including when the probe throws); a throwing probe is skipped and the next
answers; all probes throwing = `false, "unknown"`; secret answers are skipped; non-(number|string)
tokens never touch a probe; Mainline shape (no classic global) resolves on the modern probe's
throw; a probe-less client is `false, "unknown"` with no resolution; a secret resolved id is
never probed; static scan pins the interaction-distance removal and its WHY comment, plus the
three wow-ui-source citations (only Blizzard caller, API doc with no protection marker, and the
insecure `UnitDistanceSquared` consumer with the `checkedDistance` contract).

Revert-to-fail proof: in a `/tmp` copy with the pre-fix `compat.lua`, the suite exits 1 with
`lua5.1: bad argument #1 to 'IsSpellInSpellBook' (outside of expected range - got string)` and
10 FAIL lines before aborting.

## 4. Verification numbers

Standalone, final tree (2026-10-21):

| suite | result |
|---|---|
| `tests/spell_known_state.lua` (new) | 251 checks, 0 failures |
| `tests/smoke.lua` | 232 checks, 0 failures |
| `tests/shaman_state.lua` | PASS (1064 checks) |
| `tests/warrior_state.lua` | PASS (2046 checks) |
| `tests/rogue_state.lua` | 1114 checks, 0 failures |
| `tests/paladin_state.lua` | PASS (1234 checks) |
| `tests/hud_state.lua` | PASS (817 checks) |
| `tests/class_activation_state.lua` | PASS (70 checks) |
| `tests/weave_range_state.lua` | 149 checks, 0 failures |
| `tests/neutral_actions_state.lua` | PASS (7026 checks) |
| `tests/lrc_guard_state.lua` | PASS (141 checks) — at final state; see §5 |

`luacheck .` → **2 warnings / 0 errors in 87 files** (standing floor). `luacheck compat.lua` →
1 warning (`addon_name` at 36:7, standing) / 0 errors. `luacheck tests/spell_known_state.lua` →
OK, 0 warnings.

`bash tests/run.sh` captured **2026-10-21T22:14:57Z**: 44 steps, 5 failed.
Attribution (fresh `/tmp/opencode/isolate2` copy of the current tree with the PRE-FIX
`compat.lua` produced IDENTICAL results, so none of these are this lane's code):

- `hunter_state` — crashes at `hunter_ui.lua:42` `attempt to index field 'guard' (a nil value)`
  (parallel lane's file, mid-edit; crash identical on pre-fix compat).
- `bars_state` — 1 of 907: "hunter range: sweet-spot state colour (got 0.5, want 0.98)"
  (parallel lane's range-engine integration; identical on pre-fix compat).
- `main_init_state` — 47 of 950, range deadline/poll/notice checks (parallel lane's range lane;
  identical on pre-fix compat).
- `secret_guard_state` — crashes at line 1413 calling the removed wrapper; fix filed in §5
  (file unowned by this lane).
- `toc_check` — 2 failures: `unregistered: tests/spell_known_state.lua`, 42 registered / 43 on
  disk. Closes when the run.sh line in §5 lands.

An earlier capture (22:0x) also had `lrc_guard_state` red (65/170) from a mid-edit vendored
LibRangeCheck; the parallel lane landed the lib fix and it now passes 141 checks. The shared
tree was moving during verification; every red listed above was re-checked against the
pre-fix-compat isolate at the same tree state.

## 5. Filed (not edited — outside lane ownership)

1. **`tests/run.sh`** — add after line 91 (`secret_guard_state`):
   ```
   run "lua5.1 tests/spell_known_state.lua" lua5.1 tests/spell_known_state.lua
   ```
   Closes both `toc_check` failures.

2. **`tests/secret_guard_state.lua`** — the removed wrapper is still pinned at three places:
   line 90 (`local SECRET_CHECK_DISTANCE = secret(900130)`), line 203
   (`env.CheckInteractDistance = ...`), lines 1412-1415 (two `api.CheckInteractDistance` calls).
   Exact proposed replacement for 1412-1415 (delete lines 90 and 203, which become unused):
   ```lua
       check(api.CheckInteractDistance == nil,
           "R10: the protected interaction-distance wrapper is not exposed")
   ```
   This keeps an R10 pin on the removal instead of dropping the coverage. The suite should then
   run again; its count changes by -2 +1 from the last green number (owner applies and re-runs —
   the exact post-fix count is UNVERIFIED here).

3. For the record, not filed against this lane: `hunter_state` (`hunter_ui.lua:42` guard nil) and
   `bars_state` (sweet-spot colour) belong to the range-engine lane; `main_init_state` likewise.
   The compat-side consumer fix already landed: `hunter_ui.lua:891` now uses
   `api.UnitDistance("target")`.

## 6. Mutation proofs

Applied to `/tmp/opencode/mut` (copy of the working tree, never the working tree). Each mutant
was a single edit; the suite was restored and re-run green (251/0) afterwards.

| # | mutation | result |
|---|---|---|
| M1 | remove `pcall` on the original-token probe | exit 1; `lua5.1: bad argument #1 to 'IsSpellInSpellBook' (outside of expected range - got string)`; 10 FAIL lines |
| M2 | remove the id retry after a throw | 56 failures; first `TBC name: the known spell answers true (got false, want true)` |
| M3 | remove the `is_secret(known)` answer guard | 8 failures; `secret probe answer: the next probe answers instead of comparing a secret (got false, want true)` |
| M4 | let numeric tokens resolve as names (remove the string-only guard) | 2 failures; `numeric token + throwing probe: the number was probed exactly once, never retried: call count (got 2, want 1)` |
| M5 | reintroduce `api.CheckInteractDistance` | 2 failures; `static: compat.lua contains no interaction-distance call (the protected API is gone)` |
| M6 | remove the non-(number|string) token guard | 4 failures; `non-token: the classic probe was not called (got 6, want 0)` |
| M7 | strip the Blizzard caller citation (`UnitPopupSharedUtils.lua:194`) | 1 failure; `static: the comment cites Blizzard's only caller (secure popup code)` |

## 7. UNCONFIRMED

- **In-client behaviour on TBC Anniversary 2.5.6 is NOT verified here.** No client run was made;
  the sandbox reproduces the operator's reported message shape, not a live capture.
- The exact text of the deprecated shim's throw (`Deprecated_SpellBook.lua:19`) is modelled from
  the operator's BugGrabber line; the sandbox message is an approximation.
- `GetSpellInfo` returning the id as its 7th value on TBC Anniversary is the documented classic
  shape and the shape compat already uses elsewhere, but it was not re-checked against the live
  client in this lane.
- The harness numbers are a snapshot of a shared tree with parallel lanes still editing; the
  final orchestrator re-run is authoritative.
- The brief says `compat.lua` is CRLF. The file is LF (confirmed by `file`/`bench/lessons.md`);
  LF was preserved. No line-ending change was made.
