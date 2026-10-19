# compat-bl — Journal

## 2026-10-17 — Desk opened
- **Purpose:** C2 `st.api.scan_player_aura` wrapper + confirmed Bloodlust ids (BL 2825 / Heroism 32182) wired through the compat layer.
- **Scope:** compat.lua only.
- **Next step:** wait for dispatch brief in bench/briefs/; every new wrapper nil-safe, smoke-covered.

## 2026-10-17 — [signal:done] Brief executed: C2 scan + lust ids landed
- **Scope held:** compat.lua + tests/smoke.lua only; nothing else touched, no git, no lint-config changes, endings preserved (LF verified via `file`).
- **compat.lua:** header doc lines for `st.lust_spell_ids` / `st.lust_supported`; new "Bloodlust / Heroism (the lust window)" section after the GCD probe (ids 2825/32182 CONFIRMED per verify_bank §2, `st.lust_supported` family-derived Era/UNKNOWN-safe, `st.post_lust_debuff_ids = { 57723, 57724 }` registered UNCONFIRMED with in-client check note); new `api.scan_player_aura(predicate)` (frozen contract) directly under the aura wrappers, running through the file's own `api.UnitAura` wrapper (classic global on Era/TBC/Wrath, C_UnitAuras on Mainline-code) and `api.get_time()`.
- **tests/smoke.lua:** +21 checks (109→130): Era/UNKNOWN gate closed, TBC/Wrath/Forever armed, exact id lists, TBC classic-path math (remaining/stacks/nil paths/clamp/predicate args), count-of-1 rule, retail C_ path via C_UnitAuras stub.
- **Evidence:** repo `bash tests/run.sh` 33/33 green, luacheck 45 warnings / 0 errors (baseline unchanged; the 1 warning in the two touched files is pre-existing `compat.lua` `addon_name`, shifted lines only). Mutation proofs on /tmp/opencode/mut_compat-bl: baseline green on the copy; Era-gate mutation → 2 FAIL (era + unknown); nil-path mutation (`predicate` short-circuit → `0, 0`) → 1 FAIL; restored diff-identical, 33/33 green on the copy again.
- **Frozen contract restated:** `duration_remaining_seconds, stacks = st.api.scan_player_aura(predicate)`; predicate `(spell_id, name, stacks)` first-match; `(nil, nil)` = not found / no API / bad predicate; remaining from expirationTime on the `api.get_time()` axis, clamped ≥0; stacks = count > 1 else nil (family-consistent). Full restatement + option-defaults section: bench/buildout_compat-bl_2026-10-17.md.
- **Next step:** hunter/paladin lanes code against the frozen contract; options pass later; the 57723/57724 in-client check stays open until a client read confirms or kills it.
