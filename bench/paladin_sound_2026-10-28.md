# paladin-sound — the twist playback sound's AceDB `**` trap (F2.5 sibling)

- **Desk:** `paladin-sound` · **Lane id:** not stated in the dispatch (the orchestrator's
  central ledger row is `paladin-sound`; no id was provided, so none is invented here).
- **Date:** 2026-10-28
- **Status:** **DONE (offline)** — the defect is closed in the tree and proven; no
  live-client proof (§9).
- **Scope held:** `tests/paladin_state.lua` is the only file **this lane** changed.
  `classes/paladin.lua` was changed by the concurrent `latent-trap-hardening` lane (§1).
  Nothing else touched: no `config.lua`, `bars.lua`, `tests/bars_state.lua`, `widgets.lua`,
  `tests/rotationtext_state.lua`, `Libs/`, TOCs, docs, `.luacheckrc` or `tests/run.sh`.
  Version stays **2.1.3**; no git.

---

## 1. What happened: duplicate dispatch, and the attribution

This lane and `latent-trap-hardening` were dispatched with overlapping write scope on
`classes/paladin.lua`, and the other lane's brief
(`bench/briefs/brief_latent-trap-hardening_2026-10-28.md`, L1) names the **same** fix.
The timeline is the honest attribution:

| Time (-04:00) | Event |
|---|---|
| 05:12 | this lane starts: scope `classes/paladin.lua` + one test suite |
| 05:13:59 | `latent-trap-hardening` desk opened (L1 = this defect, plus L2-L4 elsewhere) |
| 05:16:18 | that lane lands the L1 fix in `classes/paladin.lua` (and hoists both choice-key reads to `rawget`) |
| 05:17 | this lane verifies the landed fix and messages the parent about the collision |
| 05:21:07 | that lane's final `classes/paladin.lua` write (restores CRLF; see §10) |
| 05:21:08 | this lane's final `tests/paladin_state.lua` write (proof + pin re-cut) |
| 05:23 | final gate: 54 steps / 0 failed |

**This lane did not rewrite the landed fix.** One writer per file
(`bench/lessons.md`); the code already met every requirement of my brief, so rewriting it
would only have stomped concurrent work and churned a 6,800-line CRLF file. What this lane
contributed is the **behavioural proof and the pin work** (§5-§7). The parent session was
messaged at 05:17 with this exact timeline; no `hands-up.md` row was filed because there is
no factual disagreement to rule — the roster reconcile is the orchestrator's call (§12).

---

## 2. The defect, confirmed by reading (and then reproduced by test)

Pre-fix `classes/paladin.lua:1151-1157` (read from the working tree at 05:15, before the
other lane's write):

```lua
local function play_twist_sound(db, key, fallback_key)
    local path = twist_sounds[key or fallback_key]
    if path == nil or PlaySoundFile == nil then
        return
    end
    PlaySoundFile(path, db.sound_channel or "Master")
end
```

- `db` is the class row from `self:get_class_table()`
  (`main.lua:233-245`; `on_bar_update` reads it unguarded, `on_twist_attempt` uses `or {}`).
- Every class row carries the `'**'` defaults metatable: `ST.<CLASS>.defaults['**'] =
  ST.bar_defaults` at `config_presets.lua:333, 460, 630, 716, 895, 970, 1107, 1284, 1357,
  1497`; the profile root's is `ST.defaults.profile['**'] = ST.class_defaults`
  (`config.lua:64`).
- AceDB's `__index` **creates a defaults-filled table, rawsets it into the saved profile and
  returns it** (`Libs/AceDB-3.0/AceDB-3.0.lua:97-103`). So `db.sound_channel` on a row that
  ships no leaf answers a truthy **TABLE**, which the old code passed to `PlaySoundFile`
  (`or "Master"` never fires — the table is truthy).
- It was latent only because `PALADIN` ships the string leaf
  (`config_presets.lua:788`). Nine of ten class rows do not.
- The call was **unpcall'd**, and the window cue runs inside the per-frame
  `on_bar_update`: a client that throws there errors out of the twist logic every tick.

---

## 3. The fix as landed (by `latent-trap-hardening`), verified against my brief

Final code at `classes/paladin.lua:1152-1177`:

```lua
local function play_twist_sound(db, key, fallback_key)
    local chosen = key
    if type(chosen) ~= "string" then
        chosen = fallback_key
    end
    local path = twist_sounds[chosen]
    if path == nil or PlaySoundFile == nil then
        return
    end
    local channel = nil
    if type(db) == "table" then
        channel = rawget(db, "sound_channel")
    end
    if type(channel) ~= "string" then
        channel = "Master"
    end
    pcall(PlaySoundFile, path, channel)
end
```

| Requirement | Where | Verdict |
|---|---|---|
| channel read with `rawget` (no metatable creation) | `:1170-1171` | **met** |
| answer must be a **string** | `:1173-1175` | **met** |
| fall back to `"Master"` | `:1174` | **met** |
| `pcall` the sound call (silent no-op on failure) | `:1176` | **met** |
| sibling sound calls checked | §4 | **met** |

**Bonus in the same edit, also verified:** both choice keys were hoisted to `rawget` at the
call sites — `sound_choice` (`:2141`) and `success_choice` (`:2204`) — closing the identical
trap where an absent `twist_sound_choice` / `twist_success_sound_choice` would have read as a
table and keyed the sound map to nil.

**Behaviour deltas, stated honestly:**
- PALADIN (the only reachable class today): no change — a real leaf and a user pick are
  honoured exactly as before.
- A row with no saved channel now yields the string `"Master"` instead of a table.
- A corrupt saved value (table/number) falls back to `"Master"` instead of reaching the
  client.
- A corrupt/absent *choice* key now falls back to the shipped cue key and plays (before, a
  metatable table keyed the map to nil and the cue was silently skipped). This is the
  documented `fallback_key` intent; it is a behaviour change for a corrupt profile only.

---

## 4. Sibling sound-call sweep of `classes/paladin.lua`

`grep -nE 'PlaySoundFile|StopSound|PlaySound[^F]' classes/paladin.lua` returns exactly:
the helper's nil probe (`:1161`), its pcall (`:1176`), and two comment mentions. There is
**no other sound call in the file** — no `StopSound`, no bare `PlaySound`. Both twist
playback paths go through the one fixed helper:

- window cue: `play_twist_sound(db, sound_choice, "pop")` — `:2142`, from `on_bar_update`;
- attempt cue: `play_twist_sound(db, success_choice, "TadaFanfare")` — `:2205`, from
  `on_twist_attempt`.

The tempting sibling **outside** this file, `main.lua:233-245 ST:get_class_table` (the plain
root read that created the row), was fixed by the same lane as L2; it is not this lane's
edit.

---

## 5. The proof (this lane)

**Suite identification:** `tests/paladin_state.lua` is the covering suite — it is the only
file under `tests/` that mentions `play_twist_sound`, and one of only two that drives
`on_twist_attempt` (the other, `tests/bars_state.lua`, is another lane's file and is out of
scope). `tests/twist_state.lua` covers the pure `twist.lua` engine, not playback.
The suite loads the **real** `classes/paladin.lua` over a frame/API stub, so the proof runs
the shipped helper, not a copy.

New **section 18**, `tests/paladin_state.lua:3863-4088` — **38 checks**, all passing:

- **Fixture: the shipped database, not a lookalike.** Loads the real vendored
  `Libs/AceDB-3.0/AceDB-3.0.lua` + `config_presets.lua` + `config.lua` in its own sandbox
  (the `rotationtext_state.lua` §7b pattern, which the neighbours used) and boots
  `AceDB:New({}, ST.defaults, true)`. It asserts on the real object:
  - the PALADIN row carries the `'**'` `__index` metatable;
  - `rawget(class_row, "sound_channel") == nil` for a row that ships no leaf (WARRIOR);
  - the **defective** plain read answers a **table** and rawsets it into the saved row
    (proved on WARRIOR *and* on the driven PALADIN row after removing its leaf).
- **S1 — attempt cue** (`on_twist_attempt`): the channel handed to `PlaySoundFile` is the
  **string** `"Master"`; the mapped TadaFanfare path is played; `rawget` of the row key stays
  `nil` (no junk written); the attempt counter still advances. Saved `"SFX"` is used; a saved
  table and a saved number both fall back to `"Master"`.
- **S2 — containment**: a `PlaySoundFile` that **throws** cannot escape the handler; the
  attempt still counts and the handler keeps running past the failed call
  (`twist_attempt_until` is set) — the old code aborted there.
- **S3 — window cue** (`on_bar_update`, per-frame path): two seals armed, swing 0.5 s from
  landing → the `pop` cue reaches `PlaySoundFile` with the string `"Master"`, creates no key,
  and the per-swing latch keeps it to one play.
- **S4 — source pins** (comment lines stripped first, because the fix's own comment quotes
  the old expression): no plain `db.sound_channel` read remains; `rawget(db, "sound_channel")`
  present; `type(channel) ~= "string"` present; the client call is `pcall`-guarded; the helper
  is defined once and called from both twist paths.

`lua5.1 tests/paladin_state.lua` → `PASS paladin_state.lua (1313 checks)`.

---

## 6. Mutation proofs (red-first)

Copies are made and mutated inside **one shell command** under a private `/tmp` directory:
this harness's `/tmp` is ephemeral per command (a first M1 attempt silently no-op'd on a
marker miss and reported a false PASS — caught, disclosed, and redone line-based; that is
the only reason the numbers below are trustworthy). Baseline on each copy:
`PASS paladin_state.lua (1313 checks)`.

| # | Mutation | Result |
|---|---|---|
| **M1** | restore the **exact pre-fix helper** (`PlaySoundFile(path, db.sound_channel or "Master")`, unpcall'd) | **21 of 1313 FAIL** — incl. `S1: the channel handed to PlaySoundFile is a STRING, never the metatable's table (got table)`, `S1: an absent channel falls back to the shipped default string (got table, want Master)`, `S1: the rawget channel read created no key on the saved row (got table, want nil)`, `S3: the window cue created no channel key (got table)`, plus every L1 pin |
| **M2** | keep `rawget` + string gate, drop the `pcall` | **5 FAIL** — both S2 containment checks, the S4 pcall pin, and both LATENT pcall pins |
| **M3** | keep the string gate + `pcall`, revert the channel to a plain class-row read | **6 FAIL** — S1/S3 "created no key (got table)", S4 no-plain-read + rawget pins, LATENT rawget pins |

M1 is the money shot: the old code hands `PlaySoundFile` a **table** — the exact defect the
brief describes. M3 is the second lesson: `pcall` + a string gate do **not** make a plain
read safe; the persistent junk key is still created, and only `rawget` prevents it.

---

## 7. Pins re-cut

- **G3 wiring pin** (pre-existing, `tests/paladin_state.lua` §17): was
  `src:find("db.lag_multiplier")`; now accepts `rawget(db, "lag_multiplier")` **or** the plain
  form, with the same intent ("the window getter reads the lag keys"). **Why:** the other
  lane's L5 sweep converted the window getter's lag reads to `rawget`
  (`classes/paladin.lua:1727-1730`), so the literal `db.lag_multiplier` form vanished. Without
  this re-cut the suite was **RED** (1 of 1276) at 05:19; the green gate in §8 depends on it.
- **S4 call-site pin** (new in this lane, so not a pre-existing pin): the first form keyed on
  the argument shape (`play_twist_sound(db, db.`); the same lane hoisted the choice keys into
  locals (`play_twist_sound(db, sound_choice, ...)`), so it was re-cut to a comment-stripped
  "1 definition + 2 calls" count against the final source.
- No other pins re-cut. The other lane's LATENT L1 pins in this suite were left untouched.

---

## 8. Gate state

`bash tests/run.sh`, run **2026-10-28 05:23 (-04:00)** on the settled tree:

- **54 steps, 0 failed**
- `luacheck .` → **2 warnings / 0 errors in 97 files**
- `tests/paladin_state.lua` alone → **PASS (1313 checks)**
- Baseline at 05:13, before either lane's L1 work → identical 54 / 0 and 2 / 0 in 97 files;
  no regression introduced by the L1 work or this suite.

Snapshot (for the orchestrator):

| file | sha256 | mtime | endings |
|---|---|---|---|
| `classes/paladin.lua` | `81b7d4cfdcf98fc93ed491cdfba576b3ecc26ce02c1b0a81aaee27791143b882` | 05:21:07 | CRLF |
| `tests/paladin_state.lua` | `fcc0fb66d5ed1ce7e898c4bf9c8c55d1f3079ef27910651f8797beb61364b92f` | 05:21:08 | LF |

Caveat: two lanes wrote into this window; this is a snapshot of the combined tree at 05:23,
not a verdict on the other lane's other files.

---

## 9. Line endings

`classes/paladin.lua` is originally **CRLF**. The other lane's 05:16 write flattened it to LF;
its 05:21 write restored CRLF — final file verified **6794 / 6794 CRLF**. `tests/paladin_state.lua`
is final **LF**, its original form. `.gitattributes` is `* text=auto eol=lf`, so even the
intermediate LF was not a packaging break; recorded here for the trail. **No action taken by
this lane** (I never edited `classes/paladin.lua`).

---

## 10. What still needs a live client (UNVERIFIED)

- `PlaySoundFile` return arity and accepted channel names (`"Master"`, `"SFX"`, `"Music"`,
  `"Ambience"`) on each target family. Offline proves the **argument type** and
  **containment**, not what the client does with them.
- That the two cues are actually heard on a real paladin profile: the window cue at its
  0.20 s audio lead-in, the attempt cue on a two-seal swing, and the per-swing latch.
- The real failure mode when the client rejects a file/channel: throw vs `false` return.
  Both are handled offline; only a client shows which one it does.
- A user-picked channel string (`"SFX"`) round-tripping through the saved profile to
  `PlaySoundFile`.
- **Not** needing a client: the `'**'` creation behaviour itself (driven over the shipped
  AceDB object offline) and the "no junk key" property.

---

## 11. Coordination note (not a technical disagreement)

Duplicate dispatch: two lanes held the same write scope on `classes/paladin.lua`
(`paladin-sound` and `latent-trap-hardening` L1). No desk disagrees on the facts or the fix;
the fix is correct and proven. The orchestrator owns the reconcile — recommended disposition:
credit the L1 code change to `latent-trap-hardening` (it wrote it) and cite this report for
the behavioural proof; keep one lane row for the defect so the publish audit does not
double-count. No `hands-up.md` row was filed.

---

## 12. Files changed by this lane

| File | Change |
|---|---|
| `tests/paladin_state.lua` | §18 added (lines 3863-4088, **38 checks**): real-AceDB `'**'` fixture + S1-S4 runtime/source proof; **G3 pin re-cut**; suite total 1313 checks. |
| `classes/paladin.lua` | **NOT edited by this lane** — L1 was landed by `latent-trap-hardening` (05:16:18, final 05:21:07); verified against the brief and proven by §18. |
