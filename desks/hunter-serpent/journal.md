# Hunter Serpent — Journal

## 2026-10-19 — Desk opened
- **Purpose:** build spec **BS-3** of `bench/filed_closure_sweep_2026-10-19.md` §7 — the hunter
  **Serpent Sting target-debuff feed** (`inputs.serpent_active` becomes a real three-state scan).
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua`, `tests/hunter_state.lua`,
  `tests/hunter_guide_state.lua`. Nothing else. No git, no lint-config change, no TOCs, no
  versions, no practice/options/config files, no other classes.
- **Enabler:** BS-1 has landed — `compat.lua:569` `api.scan_unit_aura(unit, predicate, filter)`
  (unit-generic, secret-safe, `nil, nil` when not found / not readable). `compat.lua` is OUT OF
  SCOPE for this lane.
- **Key facts (sourced in the bench sweep):**
  - The three sourced Serpent Sting ranks: **13554** (Era r1), **25295** (SoD p7 weave APL
    r9 / the Forever APL), **49001** (wowsims/wotlk `sim/hunter/serpent_sting.go`). All three
    are SIM-CONFIRMED; every id is still CLIENT-UNCONFIRMED.
  - The predicate matches **by name first and id second** ("Serpent Sting"), because the TBC
    Anniversary client resolves spells by name (its Serpent rank ids are not the sourced ones).
  - The guard semantics do NOT change: the naked-Chimera guard withholds the prompt ONLY when
    the sting is KNOWN to be down (`serpent_known == true` and `serpent_active == false`); an
    unknown debuff still allows the prompt (`hunter_guide.lua:761,801`).
- **Build shape:** the gather publishes `inputs.serpent_active` = true (the sting is up on the
  target) / false (the scan ran against a real target and the sting is not on it) / nil
  (unknown). The scan runs only when the client KNOWS a Serpent rank (`serpent_known == true`),
  because the guard cannot act otherwise — so no client pays for a scan it cannot use.
- **"the scan ran" (the false-vs-unknown discriminator):** a missing row is only an honest
  "the sting is down" when the read was COMPLETE. Two things can make it incomplete:
  no target (there is nothing to scan → unknown), and the secret-aura regime
  (`api.auras_may_be_secret()` — a restricted row can hide the sting → unknown). Outside the
  secret regime (every shipped client) a missing row is "down".
- **Rules:** nil-safe; unknown ≠ absent; no default-visible change (no new option, no new
  toggle); line endings preserved (`classes/hunter.lua` + `hunter_guide.lua` are CRLF, the two
  test files are LF); touched-lines whitespace only; mutation proofs on `/tmp/opencode` copies
  (a "secret row reads as down" mutant and an "unknown silences the prompt" mutant must each
  fail a pin).
- **Next step:** implement the gather input + the guide's input-contract comment, update the
  two suites, run the harness, prove the mutations.

## 2026-10-19 — BS-3 built: the three-state Serpent feed lands
- **Worked on:** `classes/hunter.lua` (the gather's `inputs.serpent_active` is now a real
  target scan), `hunter_guide.lua` (the input contract + the W2 note; **the rule matrix is
  untouched**), `tests/hunter_state.lua` (target-debuff fixture + the gather pins),
  `tests/hunter_guide_state.lua` (the explicit three-state engine pin + a full-loop
  gather→engine block).
- **The design decision that was not in the spec:** `api.scan_unit_aura` cannot tell "not
  found" from "could not be read" (it returns `nil, nil` for both, and its own contract
  says read nil as *unknown*). So the class proves the read's trust itself before a missing
  row may be called "down": **no target → unknown**, and **the secret-aura regime
  (`api.auras_may_be_secret()`) → unknown**. Outside the regime (every shipped client) a
  missing row is an honest "down". The regime probe is the only signal a class can read: a
  row-level secret is indistinguishable from "no row" through the shipped `api.UnitAura`
  wrapper (it degrades a whole restricted entry to nil — the R2 rule), and the house already
  uses the regime probe for exactly this (the rogue's `hud_aura_state`, the shaman's lust
  latch).
- **Also decided:** the scan runs only when `serpent_known == true` — the same gate the
  guard reads. With no known rank the guard cannot withhold anything, so no client pays for
  a scan it cannot use (pinned: an unlearned rank costs **zero** target aura reads).
- **Current state:** both hunter suites green (1060 + 1407 checks), luacheck **0 warnings /
  0 errors** on the four touched files, `luac5.1 -p` clean, CRLF preserved on the two class
  files and LF on the two test files. Both required mutants are **killed**:
  "a secret row reads as down" → 1 failing pin in `tests/hunter_state.lua`; "an unknown
  silences the prompt" → 21 failing pins in `tests/hunter_guide_state.lua` (logs
  `/tmp/opencode/mutA.log`, `/tmp/opencode/mutB.log`).
- **Out-of-scope concurrent breakage:** the sibling BS-4 lane (`desks/shaman-coe-ss`) has
  `classes/shaman.lua` in a transient state that breaks Lua 5.1's 200-local limit
  (`classes/shaman.lua:3616: main function has more than 200 local variables`). That broke
  **8 harness steps**, all of them only because they load the shaman class module. Not this
  lane's file; the orchestrator re-runs the full harness after BS-4 lands.
- **Final harness state (after the BS-4 lane repaired its file):** 41 steps, **2 failed** —
  every failing check is a **shaman** pin in a shared suite (`guide_contract.lua` 5/1041,
  `hud_state.lua` 3/674): the CoE slot (18 guide slots / an 11-slot HUD row) whose pins
  BS-4 has not updated yet. **Proven not mine** with a control copy (`/tmp/opencode/nohunter`,
  this lane's feed reverted): byte-identical failure counts and labels. Both hunter suites
  PASS inside the same run; `luacheck` is 2 warnings / 0 errors.
- **Artifacts:** `bench/hunter_serpent_2026-10-19.md` (the build record: the trust rule,
  the pins, the mutation proofs, the validation and the out-of-scope note).
- **Next step:** orchestrator validation (the lane's own scope is complete); re-run the full
  harness once the BS-4 shaman lane has landed.
