# bench/buildout_druid_bs2_2026-10-19.md — BS-2 landed (the druid Wolfshead Helm probe)

Desk: `druid-wolfshead`. Date: 2026-10-19.
Spec: `bench/filed_closure_sweep_2026-10-19.md` §7 **BS-2** (and §3 **U-03** / §4.4
**DU-16**, the items it closes). Enabler: **BS-1** (`bench/compat_probes_2026-10-19.md`) —
`api.is_item_equipped` is in `compat.lua:1121`.
Validation owner: the orchestrator. **No in-client observation was made by this desk** —
the probe is pinned offline against the real compat helper; the operator's session remains
the only in-client truth for what the client actually answers.

**Scope of this file.** One new bench artifact. The addon files changed are exactly:
`classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
`tests/druid_guide_state.lua`. `compat.lua` was **read only** (the probe already exists),
and nothing else was touched: no practice file, no option table, no config preset, no
other class, no `main.lua` / `diag.lua` / `hud.lua` / `bars.lua`, no TOC, no version, no
README / CHANGELOG / doc. No git write of any kind was performed on the addon repo.

> **One deliberate deviation from the spec's literal code — read §2 before validating.**
> The spec writes `api.is_item_equipped(8345) or nil`; that expression collapses the
> probe's proven **false** into nil (`false or nil` is nil in Lua) and contradicts the
> spec's own BS-1 contract ("false when the read is readable and no slot matches", "nil
> when the read is unavailable/secret"). The operator's brief for this lane says
> *keep the tri-state*, so the probe's answer is written as it is. Nothing else in the
> spec was reinterpreted.

---

## 1. What the spec asked, and what landed

| # | Spec item | Landed | Where |
|---|---|---|---|
| BS-2.a | Replace the "no honest probe exists" comment at `classes/druid.lua:1871-1878` with the real, sourced position | **done** | `classes/druid.lua:1873-1885` (the two-probe position: the Helm half is proven, the Furor half is not) |
| BS-2.b | Add one input, `wolfshead_equipped`, keeping the tri-state (true / false / nil) | **done** | `classes/druid.lua:1907-1916` (the gather writes it) |
| BS-2.c | The engine's input spec names it as a **reserved plug-in point**; no rule reads it | **done** | `druid_guide.lua:73-89` (the input spec), `:199-212` (the TBC REMOVED note), `:290-295` / `:382-386` (the ERA / SOD notes), `:896-900` (the branch's code comment) |
| BS-2.d | The gather's header claim ("D1 powershift probe stays blocked - no honest offline probe exists") was stale | **done** | `classes/druid.lua:22-25` (now: the Furor half is still blocked, the Helm half reads through `api.is_item_equipped`) |
| BS-2.e | The name also rides the practice input vocabulary, like the other reserved inputs (`can_powershift`, `can_shred`) | **done** | `classes/druid.lua:2944` (`DRUID_GUIDE_INPUT_NAMES`) |

**Nothing else moved.** The rule matrix is byte-identical: no rule reads the new input,
so no prompt, hold, slot or rotation text can change. There is **no default-visible
change** — the input is published and nothing consumes it.

---

## 2. The tri-state contract (why "unknown" is never "false")

The spec's literal text was `inputs.wolfshead_equipped = api.is_item_equipped(8345) or nil`.
That `or nil` would have collapsed the **proven false** into nil (`false or nil` is nil in
Lua), which would have thrown away the one readable answer the probe can give. The
operator's brief for this lane is explicit — *keep the tri-state* — so the gather writes
the probe's answer **as it is**:

```
inputs.wolfshead_equipped = api.is_item_equipped(8345)
```

| Probe answer | Meaning | Input |
|---|---|---|
| `true` | an equipped slot holds exactly item 8345 | `true` |
| `false` | the equipment read worked and no equipped slot holds 8345 | `false` |
| `nil` | the read is unavailable (no `GetInventoryItemID`), secret/restricted, or no slot was readable at all | `nil` (unknown) |

A `false` is a **proof** ("the read worked; the Helm is not worn"). A `nil` is **unknown**
("the client did not answer"). A caller that read `nil` as "not equipped" would act on a
guess about the player's gear, so the probe never reports `nil` as `false`
(`compat.lua:1095-1150`: the loop tracks whether *any* slot was readable, and a client
that reports no equipped id at all answers "unknown", not "not equipped").

The id and the check are sourced, not remembered: **8345 = Wolfshead Helm** (the
wowhead-confirmed item, `bench/ids_research_2026-10-19.md` §2) and the sim's own check is
`HasItemEquipped(8345)` in the tbc-new feralcat rotation
(`bench/class_features_drills_2026-10-19.md` §2.5 / DU-16).

---

## 3. Why the SHIFT rule stays removed (DU-16)

The powershift basis is **two** probes and only one of them is proven:

| Half | State | Evidence |
|---|---|---|
| **Wolfshead Helm 8345** | **PROVEN** (now readable) | the sim's `HasItemEquipped(8345)`; the wowhead-confirmed id; the client's own `GetInventoryItemID` over `INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED` |
| **Furor** (the 5/5 energy refund) | **UNPROVEN** | no published Furor talent id; `main.lua`'s `talent_positions` covers WRATH only, so a `GetTalentInfo` read on TBC would be a guess (`bench/druid_drills_2026-10-19.md` DU-16) |

An item probe alone cannot prove the **energy refund** — that is the whole point of the
filing. So the SHIFT branches stay removed with their constants
(`POWERSHIFT_SHORTFALL_TBC`, `SOD_POWERSHIFT_MAX_ENERGY`), `can_powershift` stays `nil`
on every tick, and the new input is published as a **reserved plug-in point** exactly
like `can_powershift` is today. The engine's own comments now say this in both files, so
the next lane does not "helpfully" wire the Helm read into a rule.

---

## 4. The pins

### `tests/druid_state.lua` §38 (new) — the gather publishes the tri-state

The sandbox gained an equipment fixture (`opts.equipment_items` → a client
`GetInventoryItemID` stub serving the equipped slot → item id) and a recording wrapper
around `api.is_item_equipped` (the queried ids are captured, so the pin can prove the
gather asks for the sim's own id). `with_equipment_range(...)` mirrors the client's
`INVSLOT_*` range into the real `_G` for the duration of the read — compat reads that
range through `rawget(_G, ...)` **at call time**, which is why the fixture alone would
not be enough.

Pinned: `true` (Helm worn) · `false` (a readable non-match — **not** nil) · `nil` (the
client cannot answer) · `nil` (no readable equipped slot at all — never "not equipped") ·
the queried id is 8345 · a stale `true` in a reused table is cleared when the read goes
unknown.

### `tests/druid_guide_state.lua` (new block, before the Claw block) — no rule consumes it

1. **Behavioural:** for six representative inputs (bear, cat, TBC, ERA, WRATH, FOREVER)
   the engine's `action`, `hold` and `hold_text` are identical with
   `wolfshead_equipped = true` and with `= false` as without the input at all.
2. **Static:** `druid_guide.lua` may **name** the input in a comment but never in code —
   the pin strips the comment tail from every line and fails on any code reference. This
   is the pin that catches a future lane re-adding a SHIFT rule.

---

## 5. The mutation proofs (on `/tmp/opencode` copies)

Script: `/tmp/opencode/bs2_mutations.py` (control copy + three mutants, each on a fresh
copy of the tree). Re-runnable: `python3 /tmp/opencode/bs2_mutations.py`.

| Mutant | Change | Killed by |
|---|---|---|
| **A — false→nil** | the gather coerces the probe's proven false into nil (`… and true or nil`) | `tests/druid_state.lua` — "a readable non-match reads false (not nil)" **FAILS** |
| **C — input not published** | the gather writes `nil` instead of the probe's answer | `tests/druid_state.lua` — "the equipped Wolfshead Helm reads true" + the queried-id pin + the false pin **FAIL** |
| **B — rule consumes it** | the TBC chain re-reads the input (`if inputs.wolfshead_equipped == true then hold = true; hold_text = "SHIFT"`) | `tests/druid_guide_state.lua` — the behavioural pin (action / hold / hold text) **and** the static code-reference pin **FAIL** |

Control: the unmutated copy passes both suites.

---

## 6. The harness

`bash tests/run.sh` → **41 steps, 0 failed**; `luacheck .` → **2 warnings / 0 errors in
83 files** (the standing floor; the two warnings are `classes/hunter.lua`'s
`SERPENT_STING_NAME` and `compat.lua`'s `addon_name`, both pre-existing and not in this
lane's files). The four files this lane touched are luacheck-clean on their own
(`0 warnings / 0 errors in 4 files`).

> **Concurrency note for the orchestrator.** The `hunter-serpent` (BS-3), `shaman-coe-fs-ss`
> (BS-4), `paladin-forever-ids` (BS-5) and `options-pass` (BS-7) lanes were writing in the
> same tree during this lane's runs (`classes/hunter.lua`, `classes/shaman.lua`,
> `classes/paladin.lua`, `config_presets.lua`, `option_tables.lua`, `nextaction_ui.lua`,
> `tests/guide_contract.lua`, `tests/hud_state.lua`, … all moved). The two whole-tree runs
> recorded above (23:11 and 23:19) were both **41 steps, 0 failed**. A later run (23:21)
> showed 10 red steps — every one of them in the concurrent lanes' files
> (`shaman_state`, `guide_contract`, `shaman_guide_state`, `bars_state`, `hud_state`,
> `rotationtext_state`, `options_load_state`, `secret_guard_state`, and the
> `luac5.1 -p` step, which trips on `classes/shaman.lua:3580` "main function has more than
> 200 local variables" — the shaman lane's in-flight edit). **This lane's suites were green
> in every run** (`tests/druid_state.lua` PASS, `tests/druid_guide_state.lua` PASS) and its
> four files are `luac5.1 -p` clean and luacheck-clean on their own.
> **The final whole-tree validation should be re-run once the concurrent lanes land**, so
> no residual crossfire is attributed to this lane.

---

## 7. Residuals (filed, not built)

1. **The Furor basis (DU-16, still open).** The SHIFT rule stays removed until a Furor
   talent id is published and a talent read that is a *knowledge* proof exists
   (`GetTalentInfo` on a verified tab/index, or `C_SpecializationInfo` on a client that
   exposes it). The Helm input is in place for that day.
2. **In-client confirm of 8345.** The read path is proven offline against the real compat
   helper and the id is web-confirmed; what the running client answers is the operator's
   session (the standing U-14 caveat).
3. **The read cost, if a rule ever consumes the input.** The probe walks the client's
   whole equipped-slot range (1..19) on every gather, and the guide's compute tick is
   0.05 s. That is ~380 inventory reads/s — harmless while nothing consumes the input,
   but a consuming rule should probably want a throttled read (the gear changes rarely).
   **Not built here**: it would change the input's freshness contract, which is a design
   decision for whoever wires the rule, and the operator's brief asked for the plain
   read.
4. **No practice/options surface.** The input is guide-side only; the practice drills
   cannot act on it (no drill reads it), and no option was added (there is nothing to
   configure).
