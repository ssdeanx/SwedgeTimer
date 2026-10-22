# rogue-compat — Journal

## 2026-10-19 — Desk opened (writer lane, brief_rogue-compat-probes_2026-10-19)
- **Purpose:** move rogue's raw `rawget(_G, ...)` client probes (`classes/rogue.lua:57-64`:
  C_Item/GetItemInfo, GetItemCount, GetItemCooldown, GetWeaponEnchantInfo, UnitGUID) into
  `compat.lua` as `st.api.*` wrappers, per the AGENTS.md cross-engine rule.
- **Scope:** ONLY `compat.lua`, `classes/rogue.lua`, `tests/secret_guard_state.lua`
  (+ minimal `tests/rogue_state.lua` stub correction). OUT: `config_presets.lua`,
  `option_tables.lua` (parallel options lane), `practice.lua`, TOCs, version, CHANGELOG.
- **Next step:** bench-read (journal, rogue_readiness §4 compat rule, rogue-cues journal,
  lessons) then implement + validate (harness + luacheck floor + mutations on /tmp/opencode).

## 2026-10-19 — Lane complete (compat probe move)
- **Worked on:** per `bench/briefs/brief_rogue-compat-probes_2026-10-19.md`, only the four
  scoped files. `compat.lua` (LF kept — verified it is NOT CRLF as the brief presumed) gained
  `api.GetItemInfo` (C_Item-first, global fallback, classic leading block, defensive table
  unfold, nil on no-probe/throw/secret), `api.GetItemCount` (nil on unknown), 
  `api.GetItemCooldown` (idle `(0,0,0)` on unknown), `api.GetWeaponEnchantInfo` (presence
  booleans), `api.UnitGUID` (string or nil). `classes/rogue.lua` (CRLF kept) drops the
  `rawget(_G, ...)` block; the five consumers call `api.*`, same guards and degrade shapes.
  `tests/secret_guard_state.lua` section 13c (control/secret/throwing/absent + C_Item
  preference/fallback + table unfold, 320 checks). `tests/rogue_state.lua` one stub fix.
  **Latent bug fixed:** the poison reminder read hasOffHandEnchant at return 4; clients
  return four values per weapon slot, so OH presence is the 5th (the 4th is the MH enchant
  id — SecureGroupHeaders.lua:686/824, BuffFrame RETURNS_PER_ITEM=4, live Deprecated_12_1_0
  shim). The old read could never show the reminder in-client. Evidence + details:
  `bench/buildout_rogue-compat_2026-10-19.md`.
- **Current state:** `bash tests/run.sh` = **37 steps, 0 failed**; luacheck **2 warnings /
  0 errors** (pre-existing floor). Mutation battery `/tmp/opencode/muts_rogue_compat.py`:
  **13/13 bitten** + clean-copy sanity PASS. Grep: zero raw client probes in
  `classes/rogue.lua`. No out-of-scope file touched (config_presets/option_tables changes
  on disk are the parallel options lane).
- **Next step:** orchestrator validation (grep proof, wrapper nil-safety, mutations), then
  fold into the rogue reconcile; smoke.lua intentionally untouched (no family-gated
  wrapper). Nothing open in this lane's files.
- [signal:done] 2026-10-19T11:35:13Z — `.signals/2026-10-19T113513Z.json` (files + harness
  result; bench artifact `bench/buildout_rogue-compat_2026-10-19.md`).
