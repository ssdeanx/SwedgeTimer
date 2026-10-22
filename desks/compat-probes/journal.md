# compat-probes — Journal

## 2026-10-19 — Desk opened
- **Purpose:** build spec **BS-1** of `bench/filed_closure_sweep_2026-10-19.md` §7 — the two
  cross-client probe helpers in `compat.lua` that the druid (Wolfshead) and hunter (Serpent
  Sting target debuff) lanes need: `api.scan_unit_aura(unit, predicate)` and
  `api.is_item_equipped(item_id)`.
- **Scope:** `compat.lua` and `tests/smoke.lua` (pins only). Class files, guide files,
  `practice*.lua`, `option_tables.lua`, `config_presets.lua`, `main.lua`, `diag.lua`,
  `hud.lua`, `bars.lua`, `tests/run.sh`, TOCs, versions, README, CHANGELOG and docs are
  owned by sibling lanes — read-only here. No git writes.
- **Next step:** implement the two helpers next to their templates, pin them in
  `tests/smoke.lua`, then run the harness + luacheck and prove the pins with mutations on
  `/tmp/opencode` copies.

## 2026-10-19 — BS-1 built
- **Worked on:** `api.scan_unit_aura(unit, predicate, filter)` — a literal generalisation of
  `api.scan_player_aura` (same 40-row cap, same no-early-break rule, same `api.get_time()`
  axis, same whole-entry secret degrade) with the unit as a parameter and the filter
  selectable (`"HARMFUL"` default = debuff scan, `"HELPFUL"` = buff scan); and
  `api.is_item_equipped(item_id)` — a tri-state probe over
  `INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED` through the existing
  `api.GetInventoryItemID` (`true` on an exact id match, `false` on a readable non-match,
  `nil` when the read is unavailable or secret). Client-source citations re-verified
  read-only in `/home/sam/wow-ui-source` (era/anniversary/titan/forever/live).
- **Current state:** *verified offline* — `bash tests/run.sh` **41 steps / 0 failed**;
  luacheck **2 warnings / 0 errors in 83 files** (the standing floor, zero new — the first
  draft of the pin block raised a third warning and was fixed by asserting the value
  instead of dropping it); `tests/smoke.lua` **232 checks / 0 failures** (26 new pins);
  **10/10 mutations killed, 0 survived** on `/tmp/opencode` copies
  (`/tmp/opencode/mut_bs1.py`, script included — every kill is a real pin failure, no
  syntax-error mutations). Bench artifact: `bench/compat_probes_2026-10-19.md`. NOT
  verified in-client — no client observation was made by this desk.
- **Open for the orchestrator / the next lanes:**
  (a) **BS-2 spec-internal conflict, settled by the pin, flagged anyway:** the spec's
  `inputs.wolfshead_equipped = api.is_item_equipped(8345) or nil` maps a `false` to `nil`
  (`false or nil` is `nil`), while the BS-2 pin demands `false` for a readable non-match.
  The pin is the testable contract, so the gather must keep the tri-state; the BS-2 lane
  should read the tri-state, not the expression.
  (b) **`false` is only reachable when the read demonstrably worked.** The mandated read
  path returns nil for three different things (global absent / restricted / empty slot —
  the client's own code reads an empty slot the same way,
  `EquipmentManager.lua:172`), so the probe answers nil when no slot reports an id at all.
  A BS-2 stub must therefore put a real (different) id in one slot to see `false`.
- **Next step:** orchestrator validates; BS-2 (druid Wolfshead) and BS-3 (hunter Serpent)
  consume the helpers. In-client check still owed: a live read of
  `api.is_item_equipped(8345)` on a character with and without Wolfshead, and a target
  debuff read on a live target.

## 2026-10-19 — [signal:done] BS-1 landed: the two compat probe helpers + 26 pins
- **Done:** `compat.lua` (`api.scan_unit_aura`, `api.is_item_equipped`) + `tests/smoke.lua`
  (26 new pins). Bench artifact: `bench/compat_probes_2026-10-19.md`. Harness 41/0,
  luacheck 2/0, 10/10 mutations killed. Offline-verified only — in-client proof is owed.
- **Next step:** orchestrator validates and dispatches BS-2 / BS-3; the two handoff notes
  above (the `or nil` conflict, and how `false` becomes reachable) travel with the bench
  file.
