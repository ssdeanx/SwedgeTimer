# bench/hunter_serpent_2026-10-19.md — BS-3: the hunter Serpent Sting target-debuff feed

Desk: `hunter-serpent`. Date: 2026-10-19.
Spec: `bench/filed_closure_sweep_2026-10-19.md` §7 **BS-3** (hunter Serpent target-debuff
feed). Enabler: **BS-1** (`api.scan_unit_aura`, `compat.lua:569`) — already in-tree.

**Scope touched (and only these):** `classes/hunter.lua`, `hunter_guide.lua`,
`tests/hunter_state.lua`, `tests/hunter_guide_state.lua`.
No git, no lint-config change, no TOCs, no versions, no `compat.lua`, no practice/options/
config files, no other class, no `main.lua` / `diag.lua` / `hud.lua` / `bars.lua` / `run.sh`,
no README/CHANGELOG/docs.

---

## 1. What changed

### `classes/hunter.lua` — the gather now publishes a real three-state feed

`inputs.serpent_active` stops being the hard-coded `nil` (`classes/hunter.lua:2348` before the
change) and becomes the result of a target scan:

| value | meaning |
|---|---|
| `true` | the sting is up on the target |
| `false` | the scan ran against a real target and the sting is **not** on it |
| `nil` | unknown — the read could not be trusted |

The pieces:

1. **`SERPENT_STING_NAME = "Serpent Sting"`** (`classes/hunter.lua:220`) — the debuff name
   every rank shares.
2. **`serpent_debuff_matches(spell_id, name)`** (`classes/hunter.lua:2051`) — the predicate:
   **the NAME first and the id second**. The name is the load-bearing key because the TBC
   Anniversary client resolves spells by name (its Serpent rank ids are not the sourced ones);
   the id leg covers the three sourced ranks (`13554` / `25295` / `49001`) on the clients that
   answer with numeric ids, and it also covers a **localized** client, where the name leg
   cannot match but the id still does.
3. **`read_serpent_active()`** (`classes/hunter.lua:2083`) — the scan:
   - it runs through `api.scan_unit_aura("target", predicate)` (BS-1's unit-generic scan:
     the 40-row cap, the no-early-break rule, the whole-entry secret degrade — a restricted
     row reads absent and the walk continues past it, so a restricted list still reports the
     match that sits below it);
   - the **match** answer is carried by the predicate's own flag, not by the scan's return
     value: `api.scan_unit_aura` returns `nil, nil` both for "not found" *and* for a match
     that carries no expiry, so its return value cannot be the match signal (the shaman's
     lust probe uses the same flag shape, `classes/shaman.lua:1731`);
   - the scan runs **only when the client knows a Serpent rank** (`serpent_known == true`,
     the same gate the guard reads): with no known rank the guard can never withhold
     anything, so no client pays for a scan it cannot use — and the "no known rank" client
     spends **zero** target aura reads (pinned).

### The one design decision worth naming: "the scan ran"

`api.scan_unit_aura` cannot tell "not found" from "could not be read" — it returns `nil, nil`
for both (its own contract: *callers must read nil as "unknown", never as "absent"*). So the
class has to establish the trust of the read itself before a missing row may be called
"the sting is down". Two things can make the read incomplete, and both are checked:

1. **No target** — there is nothing to scan, so the state is **unknown** (`nil`), never
   "the sting is down". (`UnitExists("target")`, the same global the class already reads at
   `classes/hunter.lua:2618`.)
2. **The secret-aura regime** (`api.auras_may_be_secret()`) — under it a row can be hidden
   from the read, so a missing sting is **unknown** (`nil`), never "down". This is the
   house M5 shape (the rogue's `hud_aura_state`, `classes/rogue.lua:1129`; the shaman's
   lust latch, `classes/shaman.lua:1750`): the probe answers `true` → the regime is on →
   absence is unknown; anything else (`false`, or no `C_Secrets` at all, which is every
   shipped client) → the read is complete → absence is an honest "down".

A row-level secret cannot be distinguished from "no row" by any caller of the shipped
`api.UnitAura` wrapper (it degrades a whole restricted entry to `nil` — the R2 rule), so the
**regime probe is the only honest signal available to a class**, and it is the same signal
the rest of the addon uses. The pin models the only way a row can be secret in the client: a
restricted row **under** the secret regime.

### `hunter_guide.lua` — documentation only, the rule matrix is untouched

The input contract (`hunter_guide.lua:206-228`) and the W2 rule note
(`hunter_guide.lua:274-278`) now describe the three-state feed. **The guard itself did not
change**:

```lua
and (inputs.serpent_known ~= true or inputs.serpent_active ~= false) then
```

so the naked-Chimera prompt is withheld **only** when the sting is KNOWN to be down
(`serpent_known == true` and `serpent_active == false`). An unknown debuff — no target, a
hidden row, no known rank — still allows the prompt. Both sites (the Wrath W2 rule and the
Era-SoD 5b rule) are unchanged.

---

## 2. The pins

### `tests/hunter_state.lua` (1060 checks)

The sandbox grew a target-debuff fixture (`sb.target_auras`, served on `"target"` +
`"HARMFUL"`; a row marked `secret` answers with the restricted marker, which compat's
whole-entry degrade turns into an absent row) and a `target_aura_queries` counter.

| pin | what it proves |
|---|---|
| "a client that knows a Serpent rank reports the knowledge" | the knowledge gate resolves |
| "the sting on the target reads as up (by name)" | the **name leg** matches (the TBC-shaped client, whose Serpent rank id is not one of the sourced ids) |
| "a sourced rank id matches without the English name" | the **id leg** matches (a localized client) |
| "a target without the sting reads as down" | the `false` state |
| "an unrelated debuff never matches" | the name match is exact, never a prefix ("Serpent Fang" is not the sting) |
| "no target leaves the debuff unknown" / "a client with no target spends no debuff scan" | `nil`, never "down"; and the existence check runs BEFORE the scan, so a targetless client spends no aura read |
| "a hidden debuff row reads as unknown, not as down" | **pin (b)** — a secret row is unknown, not "down" |
| "a readable row still reads as up under the secret regime" | the regime alone does not blind the scan, only a hidden row does |
| "outside the secret regime a missing sting reads as down" | the trust rule is the regime, not a guess |
| "an unlearned Serpent rank leaves the debuff unknown" / "costs no target scan" | the knowledge gate: no scan a client cannot use |

### `tests/hunter_guide_state.lua` (1407 checks)

- the engine's three-state matrix is re-pinned explicitly: `false` withholds, `true` keeps
  the prompt, and an **explicit** `nil` never withholds ("serpent: an explicit unknown debuff
  never withholds the Chimera prompt");
- a **full-loop** block was added: a Wrath MM client that knows the Chimera Shot and a
  Serpent rank, gathered and evaluated through the real engine —
  - the sting on the target → `serpent_active == true` → action `chimera`;
  - the sting not on the target → `serpent_active == false` → action `steady` (the naked
    Chimera is withheld);
  - no target → `serpent_active == nil` → action `chimera` (an unknown never withholds).

---

## 3. The mutation proofs (`/tmp/opencode` copies)

Both required mutants were built on a copy of the tree and killed by a pin.

| mutant | change | result |
|---|---|---|
| **"a secret row reads as down"** | `classes/hunter.lua`: the secret-regime check is disabled (`if false and ...`) → a hidden row would read as `false` | `tests/hunter_state.lua` → **1 of 1060 checks failed**: "serpent: a hidden debuff row reads as unknown, not as down (got false, want nil)" |
| **"an unknown silences the prompt"** | `hunter_guide.lua`: both guard sites become `and (inputs.serpent_active == true) then` → an unknown withholds | `tests/hunter_guide_state.lua` → **21 of 1407 checks failed**, among them "serpent: an explicit unknown debuff never withholds the Chimera prompt" and "serpent: an unknown debuff never withholds the Chimera prompt" |

Logs: `/tmp/opencode/mutA.log`, `/tmp/opencode/mutB.log`. Copies:
`/tmp/opencode/mut-serpent-a`, `/tmp/opencode/mut-serpent-b`.

---

## 4. Validation

- `lua5.1 tests/hunter_state.lua` → PASS (1060 checks)
- `lua5.1 tests/hunter_guide_state.lua` → PASS (1407 checks)
- `luacheck classes/hunter.lua hunter_guide.lua tests/hunter_state.lua tests/hunter_guide_state.lua`
  → **0 warnings / 0 errors** (the tree floor is 2–3 warnings / 0 errors; the four files add
  none)
- `luac5.1 -p` on the four touched files → clean
- line endings preserved: `classes/hunter.lua` and `hunter_guide.lua` stayed **CRLF**, the
  two test files stayed **LF**; touched lines carry whitespace only (no reindentation of
  neighbouring code)
- **full harness (`bash tests/run.sh`):** the final run reported **41 steps, 2 failed** — and
  every failing check is in the **shaman** section of a shared suite (`guide_contract.lua`
  5/1041 and `hud_state.lua` 3/674): the concurrent BS-4 lane's CoE slot (18 guide slots /
  an 11-slot HUD row) whose pins it has not updated yet. Both hunter suites PASS inside
  that same run (`tests/hunter_state.lua`, `tests/hunter_guide_state.lua`), as do
  `shaman_state`, `shaman_guide_state`, `secret_guard_state`, `bars_state`,
  `rotationtext_state`, `main_init_state`, `toc_check`, `wiring_check` and `luacheck`
  (2 warnings / 0 errors). Earlier in the session the same crossfire also broke the
  `luac5.1 -p` step and five more suites, through the shaman lane's transient
  200-local overflow in `classes/shaman.lua` (see below).

### The remaining reds are NOT this lane's (proven with a control copy)

A copy of the tree at `/tmp/opencode/nohunter` with **this lane's feed reverted** (the single
line `inputs.serpent_active = read_serpent_active()` → `nil`) produced **byte-identical**
failures:

```
guide_contract.lua      5 of 1041 checks failed   (all "shaman contract: ...")
hud_state.lua           3 of  674 checks failed   (all "shaman: ...")
shaman_guide_state.lua  3 of 1388 checks failed   (all "shaman: ...")
```

Same counts, same labels as the run with the feed in place — so the reds are the sibling
lane's crossfire, not a regression from this lane.

### Out-of-scope concurrent breakage (NOT this lane's file)

Earlier in the session the sibling **BS-4** lane (`desks/shaman-coe-ss`) had
`classes/shaman.lua` in a state that fails Lua 5.1's 200-local limit:

```
luac5.1: classes/shaman.lua:3616: main function has more than 200 local variables
```

That broke **8 harness steps** at the time (every one of them only because they load the
shaman class module). `classes/shaman.lua` is **out of this lane's scope** and was not
touched here; the lane has since repaired it, and the remaining reds are its pin updates.

---

## 5. Sources

- The three sourced ranks: `13554` (Era r1), `25295` (the SoD p7 weave APL's Serpent 25295 r9
  and the Forever APL's Serpent 25295 upkeep), `49001` (wowsims/wotlk
  `sim/hunter/serpent_sting.go`) — SIM-CONFIRMED, all three still CLIENT-UNCONFIRMED, exactly
  as `bench/filed_closure_sweep_2026-10-19.md` §7 BS-3 states.
- The name-first rule: the TBC Anniversary client resolves spell queries by **name**, never
  by a bare id (`bench/lessons.md:29-32`, the operator rule) — the same rule the rogue's
  `find_unit_aura` already applies (`classes/rogue.lua:332-361`).
- The M5 secret-regime probe: `compat.lua:613` `api.auras_may_be_secret()`.
- The enabler: `compat.lua:569` `api.scan_unit_aura(unit, predicate, filter)`.

## 6. What is NOT closed by this lane

The three ids stay **CLIENT-UNCONFIRMED** (no in-client `GetSpellInfo` yet) and the
**in-client behaviour** of the debuff read stays operator-owned (the standing U-14 caveat).
What this lane closes is the filed **debuff source** (H-04 / U-07): the guard's input is a
real three-state scan instead of a hard-coded `nil`.
