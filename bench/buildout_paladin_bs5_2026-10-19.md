# bench/buildout_paladin_bs5_2026-10-19.md — BS-5 landed (paladin Forever ids / hard wait / LCD counter)

Desk: `paladin-forever-ids`. Date: 2026-10-19.
Spec: `bench/filed_closure_sweep_2026-10-19.md` §7 **BS-5** + §8 **JE-1** (BS-8 item 1,
class-side half).
Validation owner: the orchestrator (no in-client observation was made by this desk).

**Scope of this file.** One new bench artifact. The addon files changed are exactly:
`classes/paladin.lua`, `nextaction.lua`, `tests/paladin_state.lua`, and the **paladin
section only** of `tests/guide_contract.lua`. `nextaction_ui.lua` was inspected and left
byte-identical (see §4). No git write of any kind was performed on the addon repo.

---

## 1. What the spec asked, and what landed

| # | Spec item | Landed | Where |
|---|---|---|---|
| BS-5.1 | Fill the two deliberately-empty Forever id tables (`1311703` Echo of Command, `1311704` Echo of Righteousness), keep the name-resolution path as the primary key, rewrite the "deliberately EMPTY" comment to *web-confirmed, client-unconfirmed, name-resolved* | **done** | `classes/paladin.lua:99-123` (tables + comment), `:197-232` (the discipline), `:506-532` (the latch), `:584-597` (the aura match) |
| BS-5.2 | Add the Forever **Holy Strike** id (`10333`) to the same discipline | **done** | `classes/paladin.lua:115-123` (table), `:524-532` (the probe), `:3175-3185` (the gather's plug-in point), `nextaction.lua:127-135` (the engine's contract line) |
| BS-5.3 | Render the SoD strictSequence **hard wait** in the guide's HOLD/RIDE overlay | **already in the tree — verified and pinned** (no code change was needed) | `nextaction_ui.lua:596-603` (the render, untouched), `tests/guide_contract.lua:1329-1371` (the new pin) |
| BS-8.1 | A counter for a failed `pcall(LCD.Register, …)` that the shared engine's runtime-diag line can read | **done (class side only)** | `classes/paladin.lua:59-65` (the counter), `:390-400` (the increment) |

---

## 2. The id discipline (why a wrong id cannot produce a wrong prompt)

The sweep's rule: the ids are WEB-CONFIRMED but CLIENT-UNCONFIRMED, so the **name** must be
the key and the id only a confirmation. The class already has a name-resolution path
(`resolve_spell_name` → `api.GetSpellInfo` on the id — the same path the TBC name boxes and
the Bloodlust labels use). The new helper is one function:

```
confirmed_forever_id(ids, expected_name)
  -> the confirmed id whose OWN client-resolved name is the expected name
  -> nil when the client cannot name the id yet (cold book / a names-only client)
  -> nil when the id is WRONG (the client answers a different spell's name)
```

Three consequences, each pinned:

1. **The latch only reads "down" for a proven id.** `has_echo_command` / `has_echo_twist`
   stay `nil` (unknown) until the client names the id; only then does an absent aura read
   as `false` (down) and the seal degrade for a reseal. A wrong or unproven id therefore
   leaves the archived seal input in place — the guide cannot prompt a wrong reseal.
2. **The aura match is name-primary.** The aura must carry the expected name *and* the
   proven id; the raw id never latches anything on its own.
3. **Nothing changes for a client that has not confirmed the id.** On any client whose
   spell data does not name `1311703` / `1311704` / `10333` (every client today, including
   1.60.x until the operator's in-client check), the state is unknown and the behaviour is
   the archived one. The 1.60.x `GetSpellInfo` is the operator's session.

**Localization limit (documented, safe).** The anchors are the web-confirmed English names
(wowhead's redirect slugs), compared verbatim. A non-English client therefore stays
*unknown* — inert — rather than risking a wrong match. The extension point is the anchor
list in `classes/paladin.lua:221-223`.

**The `sor_forever_ids` table stays empty on purpose.** No source names an id for Forever's
*Seal of Righteousness* (a different spell from the Echo auras), so that table keeps its
"deliberately EMPTY until GetSpellInfo confirms" standing; the comment now says so
explicitly, so the two tables cannot be confused.

---

## 3. Holy Strike (10333) — a plug-in point, not a prompt

Holy Strike is a spell, not an aura, so the resolved id is asked about in the spell book:

* `self.holy_strike_known` — `nil` (unknown) until the client proves the id, then the
  book's own answer (`true` / `false`).
* `inputs.holy_strike_known` — the same value, published by the gather as a **plug-in
  point**. The engine does not read it: the paladin's ten guide slots are frozen and have
  no Holy Strike slot, and a slot-budget ruling is owed before one is added (the Forever
  sim's APL casts Holy Strike second, after Judgement — `bench/paladin_rotation_audit_2026-10-19.md`
  §Forever GAP). Nothing prompts on it, so this is a no-default-visible-change wiring.

`nextaction.lua:127-135` now states the standing instead of the old "no sourced spell id
and is not probed" line.

---

## 4. The hard-wait render was already in the tree

BS-5.3 asks the frame to show the SoD strictSequence hard wait in the guide's HOLD/RIDE
overlay. Reading the tree first showed the render **already exists**:
`nextaction_ui.lua:596-603` paints `WAIT` in the priority chain
(STOP → PULL → OOM → WAIT → HOLD/RIDE), and the provider already feeds it
(`classes/paladin.lua:3597` `out.hard_wait = raw.hard_wait == true`). The engine publishes
it (`nextaction.lua:861`).

One defensive edit was tried — adding `or out.hard_wait == true` to the overlay's light
condition — and **reverted**: the engine only publishes the wait together with a hold, so
the extra term is dead code today and no pin could kill it. `nextaction_ui.lua` is
therefore byte-identical to its pre-lane state (verified: same size, same CRLF count, same
content). What the lane owes that file is the **pin**, which is what landed:

* `tests/guide_contract.lua:1329-1371` — a held twist on a strict build lights the HOLD
  overlay and the overlay reads `WAIT`; the same state without `strict_sequence` keeps the
  archived `RIDE`; the frame still carries exactly **ten** slots.

---

## 5. The LCD registration counter (BS-8 item 1, class side)

`pcall(LCD.Register, LCD, addon_name)` dropped its result, so a library-side failure was
invisible (the guide silently fell back to its hardcoded seal length). Now:

* `ST.PALADIN.lcd_register_errors` — module-level counter, initialised to 0 at load
  (`classes/paladin.lua:59-65`).
* The failure path increments it **exactly once** (`classes/paladin.lua:384-399`); a healthy
  registration counts nothing.

**The reader is the engine lane's.** `main.lua`'s `print_runtime_diag` should read
`st.PALADIN.lcd_register_errors` (the same shape as the existing
`hud_cleu_register_errors` line) and print something like
`paladin_lcd_register_errors=N`. Until that reader lands the counter is correct and
harmless, as the brief allows. `main.lua` was **not** touched by this lane.

---

## 6. Verification

| Check | Result |
|---|---|
| `bash tests/run.sh` (whole harness) | **41 steps, 0 failed** |
| luacheck (whole tree) | **2 warnings / 0 errors** — the standing floor (both pre-existing: `compat.lua:36`, `main.lua:81`); 0 warnings in every file this lane touched |
| `tests/paladin_state.lua` | **PASS, 663 checks** (was 643) |
| `tests/guide_contract.lua` | **PASS, 1040 checks** (was 1035) |
| Line endings | `classes/paladin.lua` and `nextaction.lua` stay CRLF (CR count == line count); the two test files stay LF; `nextaction_ui.lua` unchanged |

### Mutation proofs (`/tmp/opencode/bs5-mut`, a copy of the tree)

| # | Mutation | Killed by |
|---|---|---|
| M1 | the Echo latch falls back to the raw id (the name stops being the key) | `paladin_state`: "a wrong id never latches (the name is the key)" |
| M2 | the confirmation drops the name check (any id counts as proven) | `paladin_state`: "a wrong id never latches (the name is the key)" |
| M3 | the Holy Strike id is removed from the table | `paladin_state`: "the Holy Strike id is in the table" |
| M4 | the failed-registration counter increment is dropped | `paladin_state`: "a failed registration counts exactly once" |
| M5 | the `WAIT` render branch is removed from the overlay | `guide_contract`: "the overlay reads WAIT" |
| M6 | the provider stops feeding `out.hard_wait` | `guide_contract`: "the overlay reads WAIT" |
| M7 | the Echo latch reads "down" even when the id is unconfirmed | `paladin_state`: "an unconfirmed id stays unknown" |

**7 / 7 killed.** Script: `/tmp/opencode/bs5_mutations.py` (restores the pristine files
after each mutation and re-runs both suites green).

---

## 7. Left for other lanes / the operator

| Item | Owner | Why it is not here |
|---|---|---|
| the runtime-diag line that reads `st.PALADIN.lcd_register_errors` | the shared-engine lane (`main.lua`) | out of this lane's scope by instruction; the class half is landed and pinned |
| a Holy Strike guide slot + a rule that reads `inputs.holy_strike_known` | a future paladin lane, after a slot-budget ruling | the ten slots are frozen; the plug-in point is landed and documented |
| the 1.60.x `GetSpellInfo` for `1311703` / `1311704` / `10333` (and the localized names if the client is not English) | the operator's in-client session | the only way to turn a web-confirmed id into a client-confirmed one; until then the state stays unknown and nothing changes |
| Forever's Seal of Righteousness id | still filed (no source names one) | `sor_forever_ids` stays empty on purpose |
