# bench/compat_probes_2026-10-19.md — the BS-1 compat probe helpers

Desk: `compat-probes`. Date: 2026-10-19. Build spec: `bench/filed_closure_sweep_2026-10-19.md`
§7 **BS-1**. Lane: `compat-probes` (new). Depends on: nothing. Enables **BS-2** (druid
Wolfshead) and **BS-3** (hunter Serpent Sting target debuff).

**Scope landed:** `compat.lua` (two helpers) and `tests/smoke.lua` (24 pins). No other file
was touched: no class file, guide file, `practice*.lua`, `option_tables.lua`,
`config_presets.lua`, `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`, `tests/run.sh`, TOC,
version, README, CHANGELOG or doc. No git write of any kind was performed. The only git
commands run were **read-only** `git show` / `git grep` against the external client-source
mirror `/home/sam/wow-ui-source` (explicitly sanctioned by the Phase-6 brief).

**Proof status:** *verified offline* (harness + luacheck + mutation proofs on
`/tmp/opencode` copies). *Not verified in-client* — no client observation was made by this
desk; the operator's session remains the only in-client truth.

---

## 1. What landed

### 1.1 `api.scan_unit_aura(unit, predicate, filter)` — `compat.lua:545-603`

A literal generalisation of `api.scan_player_aura` (`compat.lua:514-543`), placed directly
after it. Everything the template has, it keeps:

| property | template | new helper |
|---|---|---|
| row cap | 40 (`scan_player_aura_index_max`, the same local) | the same 40 |
| no-early-break (R2) | a nil row is "no match at this index" | identical |
| time axis | `api.get_time()` | identical |
| secret degrade | whole-entry, from the wrapper at `compat.lua:456-488` | identical |
| predicate | `(spell_id, name, count)`, first match wins | identical |
| return shape | `remaining, stacks` on the GetTime domain | identical |

The only changes are the **unit** argument and the **filter**:

* `filter` selects the aura list. `"HARMFUL"` is the **default** (a debuff scan);
  `"HELPFUL"` is the buff scan. Any other value falls back to `"HARMFUL"`, so a typo can
  never silently scan the wrong list.
* `unit` must be a non-empty string; anything else answers `nil, nil` (a nil unit would
  raise inside the client's `UnitAura`, so this is the nil-safe guard).

**Contract (documented in the code):** returns `nil, nil` when not found, when the unit
carries no readable aura, when no aura API exists on the client, when the unit is not a
usable unit string, or when the predicate is not a function. **Callers must read nil as
"unknown", never as "absent"** — a target debuff that could not be read is not a target
without that debuff.

### 1.2 `api.is_item_equipped(item_id)` — `compat.lua:1095-1149`

Placed in the inventory-items section, next to its template `api.GetInventoryItemID`
(`compat.lua:986`). It reads the **existing** wrapper — the unit fix (`"player"`), the
absent-global guard and the secret degrade are the wrapper's, not this function's.

* The slot range is the client's own: `INVSLOT_FIRST_EQUIPPED .. INVSLOT_LAST_EQUIPPED`
  (1..19, `INVSLOT_HEAD .. INVSLOT_TABARD`), read through `rawget(_G, …)` (the addon's
  undefined-global discipline — the constants are not in the annotation set of
  Mainline-code clients).
* `true` only on an exact id match; `false` when the read is readable and no slot matches;
  `nil` when the read is unavailable or secret, when the client does not define the
  `INVSLOT_*` range, or when the id is not a number. **Unknown is never reported as false.**

**One judgment call the downstream lanes must know (read this before writing the BS-2
pin).** The mandated read path (`api.GetInventoryItemID`) returns **nil for three different
things**: the global is absent, the reading is secret, and the slot is simply empty (the
client's own code reads an empty slot the same way —
`classic_era:Interface/AddOns/Blizzard_FrameXML/Wrath/EquipmentManager.lua:172`,
`return nil; -- Slot was empty already;`). The probe therefore treats "at least one slot
read a non-nil id" as the evidence that the read works, and answers **nil (unknown)** when
no slot reports an id at all. Consequence for the callers:

* a stub that returns a real id for one slot (e.g. a different item in the head slot)
  → **false** for a non-match ✓ (this is the shape the BS-2 pin needs);
* a client without `GetInventoryItemID`, or a restricted read → **nil** ✓;
* a client that reports no equipped id at all (a character with nothing equipped) →
  **nil**, not false. That is the safe direction and it follows the spec's own rule
  ("unknown ≠ false"), but it means `false` is only reachable when the read demonstrably
  worked.

## 2. Client-source citations (read-only, this session)

Verified in `/home/sam/wow-ui-source` (`git show` / `git grep`, no writes):

| fact | source | branches |
|---|---|---|
| `INVSLOT_FIRST_EQUIPPED = INVSLOT_HEAD` (1) and `INVSLOT_LAST_EQUIPPED = INVSLOT_TABARD` (19) | `Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:173,192` | classic_era, classic_anniversary, classic_titan |
| the same pair | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:136,155` | origin/forever (1.60.1.70374) |
| the same pair | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:153,172` | live (12.1.0.69814) |
| an empty slot reads nil | `Interface/AddOns/Blizzard_FrameXML/Wrath/EquipmentManager.lua:172` | classic_era, classic_anniversary, classic_titan |
| `GetInventoryItemID("player", invSlot)` exists | `Interface/AddOns/Blizzard_FrameXML/Wrath/EquipmentManager.lua:88,170,279,325` | classic_era, classic_anniversary, classic_titan |
| the same global | `Interface/AddOns/Blizzard_ActionBar/WoWLabs/ActionButtonOverrides.lua:470`, `Interface/AddOns/Blizzard_BoostTutorial/Blizzard_TutorialLogic.lua:1149,1305` | origin/forever, live |

Client versions read: classic_era = 1.15.9.70003, classic_anniversary = 2.5.6.70006,
classic_titan = 3.80.2.69815, origin/forever = 1.60.1.70374, live = 12.1.0.69814.

## 3. The pins (`tests/smoke.lua`, 26 new checks; the file is now 232 checks / 0 failures)

**`api.scan_unit_aura`**
1. the target debuff is found (`expirationTime - now` on the `api.get_time()` axis);
2. the scan reads the unit it was given;
3. the **default filter is the debuff filter** (`"HARMFUL"`);
4. the default debuff scan finds the debuff and does **not** see a buff;
5. an explicit `"HELPFUL"` filter finds the buff (the buff-scan half of the contract);
6. a non-match → `nil, nil`; a nil predicate → `nil, nil`; a nil unit → `nil, nil`;
7. a unit with no readable aura → `nil, nil`;
8. no aura API on the profile → `nil, nil`;
9. the **Mainline `C_UnitAuras` path** (retail profile, Forever shares it): the match is
   found, a single application reads as unstacked, a non-match → `nil, nil`;
10. **secret (R2):** a restricted row above the match does not truncate the walk, and the
    restricted row itself is **not** a match — it reads as "not found", never as a truncated
    match. The test drives the wrapper's own secret guard with `issecretvalue`, so the
    degrade is exercised, not simulated by a nil row.

**`api.is_item_equipped`**
11. a stubbed head slot holding 8345 → `true`;
12. a readable non-match (a different id in the head slot) → `false`;
13. a non-numeric id → `nil`;
14. no `GetInventoryItemID` → `nil` (not false);
15. a restricted read → `nil`, not false;
16. no `INVSLOT_*` range → `nil`.

## 4. Proof set (all run on the landed tree)

* `bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0 errors in 83
  files** — the standing floor (both warnings pre-existing and KEEP-ruled:
  `compat.lua:36` unused `addon_name`, `main.lua:81` `table.pack`). Zero new warnings: the
  first draft of the pin block raised a third warning (an overwritten `stacks`), which was
  fixed by asserting the value instead of dropping it.
* `lua5.1 tests/smoke.lua` → **232 checks, 0 failures** (26 new).
* **Mutation proofs on `/tmp/opencode` copies** (`/tmp/opencode/mut_bs1.py`, script
  included; it copies the repo minus `.git`/`docs`/`Libs`, mutates `compat.lua`, and
  requires the smoke suite to go red): **10/10 killed, 0 survived** —
  M1 default filter flipped to HELPFUL · M2 early break on a nil row (R2) · M3 the unit
  argument ignored · M4 an unreadable read answered false · M5 an empty slot treated as
  unreadable · M6 the exact-id comparison dropped · M7 the wrapper's secret guard bypassed
  · M8 a missing `INVSLOT_*` range answered false · M9 the whole-entry secret degrade
  removed · M10 the shared 40-row cap collapsed to 1. Every kill is a real pin failure
  (no syntax-error mutations).

## 5. Handoff to the two enabled lanes

**BS-2 (druid Wolfshead)** — `api.is_item_equipped(8345)`:
* `true` → the head slot holds Wolfshead;
* `false` → the read worked, Wolfshead is not equipped (stub **one slot with a real id**,
  otherwise the answer is `nil`);
* `nil` → unknown (no `GetInventoryItemID`, a restricted read, or no `INVSLOT_*` range).
* The spec's line `inputs.wolfshead_equipped = api.is_item_equipped(8345) or nil` maps a
  `false` to `nil` (`false or nil` is `nil`), while the BS-2 pin wants `false` for a
  readable non-match. Those two cannot both hold; the pin is the one that carries the
  information, so the gather should keep the tri-state (`true` / `false` / `nil`) rather
  than collapse it. **The orchestrator rules on this** — it is a spec-internal conflict, not
  a code question, and BS-2 owns the gather.

**BS-3 (hunter Serpent Sting)** — `api.scan_unit_aura("target", predicate)`:
* the default filter is the **debuff** list, so the call reads the target's debuffs with
  no third argument;
* `nil, nil` → unknown (no aura API, no readable debuff on the target, a non-function
  predicate) — never "the sting is down";
* the predicate gets `(spell_id, name, count)`. `spell_id` can be nil on a client without
  numeric ids, which is why the spec's "name first, id second" ordering is the right one;
* a restricted debuff row reads as not-found and the walk continues past it, so a
  restricted list does not turn into a truncated answer.

## 6. What this desk did NOT do

* No in-client observation of any kind (the two probes are unproven in a live client).
* No change to any class file, guide file, option/config file, `main.lua`, `diag.lua`,
  `hud.lua`, `bars.lua`, `tests/run.sh`, TOC, version, README, CHANGELOG or doc.
* No git write, no branch, no commit, no lint-config change.
* No new user-visible toggle and therefore no default-visible change: both helpers are new
  callables with no caller in the tree yet.
