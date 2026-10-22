# buildout: rogue-compat-probes (2026-10-19)

Desk: rogue-compat. Brief: `bench/briefs/brief_rogue-compat-probes_2026-10-19.md`
(writer lane). Scope executed: `compat.lua`, `classes/rogue.lua`,
`tests/secret_guard_state.lua`, `tests/rogue_state.lua` (one stub correction).

## What changed

- `compat.lua` (LF kept) — new section between Totems and Clock:
  - `api.GetItemInfo(item)` — C_Item-first probe chain, global fallback; classic
    leading block (name, link, quality, level, minLevel, class, subclass);
    table-shaped read unfolded to the same positions; nil on no-probe / throw /
    missing name / any secret field.
  - `api.GetItemCount(item)` — count or nil (no probe, throw, secret).
  - `api.GetItemCooldown(item)` — classic (start, duration, enabled); idle
    `(0, 0, 0)` on no-probe / throw / secret (mirrors GetInventoryItemCooldown).
  - `api.GetWeaponEnchantInfo()` — normalized presence booleans
    `has_mainhand, has_offhand`; nil, nil on no-probe / throw / non-boolean /
    secret.
  - `api.UnitGUID(unit)` — guid string or nil (no probe, throw, secret,
    non-string).
- `classes/rogue.lua` (CRLF kept) — the load-time `rawget(_G, ...)` probe block
  (`:57-64` pre-change) is gone; the five consumers call `api.*` only. Copy
  changes only where the probe source changed (header line, probe comment,
  poison-reminder comment). `tea_item_count`, `tea_item_cooldown`,
  `item_subclass`, `poison_reminder_text`, `get_time_to_die` guid read — same
  guards, same degrade shapes.
- `tests/secret_guard_state.lua` (LF) — new section 13c: control / secret /
  throwing / absent pairs for all five wrappers, C_Item preference and
  C_Item-alone fallback builds, table-unfold pins, plus sandbox stubs
  (`omit_compat_probes` / `c_item` flags). Suite now 320 checks, 0 failures.
- `tests/rogue_state.lua` (LF) — the `GetWeaponEnchantInfo` stub corrected to
  the real client shape (below); semantic pins unchanged, 317/0.

## Latent bug found and fixed (position of hasOffHandEnchant)

The cues-lane consumer read `pcall(...)` as `ok, has_mh, _, _, has_oh` — the
**4th** return — and the test stub mirrored that. The clients return **four
values per weapon slot**, so hasOffHandEnchant is the **5th** (the 4th is the
mainhand enchant id):

- `wow-ui-source` classic_era / classic_anniversary / classic_titan:
  `SecureGroupHeaders.lua:686` and `:824` read hasOffHandEnchant at position 5;
  `BuffFrame.lua:719` + `UpdateTemporaryEnchantmentBuffs` (`RETURNS_PER_ITEM = 4`).
- live / origin/forever: `Deprecated_12_1_0.lua` shim writes four values per
  slot (offset+3 = enchantID) behind `C_PaperDollInfo.GetTemporaryEnchantmentInfo`.

With position 4 read as a boolean, `type(has_oh) ~= "boolean"` failed on a real
client and the poison reminder could never show. compat now normalizes to
presence booleans (reads 1 and 5) and the suite pins the position (mutation
"OH presence is the 5th value, never the 4th" bites).

## Validation (all on the in-tree state unless noted)

- `bash tests/run.sh`: **37 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the pre-existing KEEP floor: compat.lua:36 `addon_name`, main.lua:74
  `table.pack`).
- `tests/secret_guard_state.lua` 320 checks 0 failures;
  `tests/rogue_state.lua` 317 checks 0 failures.
- Mutation battery `/tmp/opencode/muts_rogue_compat.py` on a `/tmp/opencode`
  copy: **13/13 bitten** (enchant position, non-boolean coercion, item-info
  secret, count secret, cooldown secret, guid secret/non-string, C_Item
  preference, table unfold order, absent count, absent cooldown shape, class
  poison guard, class guid unit, rawget-return guard) + clean-copy sanity PASS
  for both suites.
- Grep proof: zero `rawget` / direct client probes in `classes/rogue.lua`
  (34 `api.` call sites).
- Line endings: brief said "compat.lua are CRLF — verify" — **verified wrong**:
  `compat.lua` is LF (0/1230 CR lines) and was kept LF; `classes/rogue.lua` is
  CRLF (1224/1224) and was kept CRLF.
- `tests/smoke.lua` untouched: no new wrapper is family-gated (all are probe
  chains with absent-probe shapes), so no new client-profile assertion applies.

## Residuals / notes

- The defensive table-shaped `GetItemInfo` branch moved from the class module
  into compat unchanged; no checked branch documents a table return
  (ItemDocumentation.lua documents the multi-return on live / classic_era /
  origin/forever), so it is pinned as a defensive path only.
- Poison **charges** remain unrendered (UNCONFIRMED, rogue_deep §5.8) — no
  change.
- No out-of-scope file touched; `config_presets.lua` / `option_tables.lua`
  changes on disk are the parallel options lane.
