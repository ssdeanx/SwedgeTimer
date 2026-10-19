# buildout hud-reflow — hidden-slot row reflow (2026-10-17)

Date: 2026-10-17. Desk: hud. Brief: `bench/briefs/brief_hud-reflow_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").
Scope held: `hud.lua` + `tests/hud_state.lua` only (both owned by this lane per the brief). No git. No lint-config. Endings preserved (hud.lua CRLF 1149/1149 CR lines; tests/hud_state.lua LF, 0 CR).

## 1. Design — reflow-on-hidden-flip, deferred outside combat

Layout used to count toggle-`wanted`, not liveness, so a provider-hidden slot (runeless-Era Mangle, dead TF/Berserk) left a gap until a settings change reflowed (hud-grade §5 finding #2). The fix tracks last hidden state per icon and reflows on flip:

- `create_icon`: `f.last_hidden = false` baseline — a live row never shifts on boot.
- `update_display`: after reading each wanted slot's state (the single provider call, unchanged), compares `s.hidden` against `icon.last_hidden`. First observation (`nil`) baselines without reflowing; a later flip sets the flag and marks `reflow_needed`. `s == nil` leaves liveness untouched (previous behavior). The flip's hide/show + glow-stop paint runs inline as before; only the row geometry moves to the post-loop reflow.
- New `HUD.reflow_row(self)`: layout-only — recomputes count/span/size/positions from `icon_effective` (toggle want × liveness), same match-bar-width math as `apply_settings`. Makes **no provider calls** and does **not** call `update_display`.
- `apply_settings`: counts and positions by `icon_effective` instead of bare `wanted` (same helper, no drift between the two layout paths). Frame scale/position/mouse, border, font handling untouched.
- Local helper `icon_effective(icon)` = `icon.wanted and icon.last_hidden ~= true`.

## 2. Binding-constraint arguments (why the deferral was safe to lift)

- **Exactly-once provider pin (HS §5):** `update_display` still calls each wanted slot's provider at most once per tick. `reflow_row` reads only the db + hand table (via the same `matched_icon_size` path `apply_settings` uses) — zero `GetSpellInfo`/`GetSpellCooldown`/`UnitAura` traffic. Pinned: §18 counts 8 provider calls for one druid tick, 5 for one paladin hide/revive tick.
- **At-most-once-per-tick-per-slot:** the reflow deliberately does not call `update_display` (that would re-run every provider and double the tick). A settings-change reflow still flows through `apply_settings` → one trailing `update_display` → one provider pass, unchanged.
- **Combat-safe:** `reflow_row` touches only non-secure row frames (`SetSize`/`ClearAllPoints`/`SetPoint`/`Show`/`Hide`, glow stop — the same calls the per-tick paint already makes in combat). Creation stays lockdown-gated in `ensure_created`. Under lockdown the flip path sets `HUD.pending_apply = true` instead of reflowing, and the existing `on_update` pending branch applies it (through `apply_settings`, which reads the same `icon_effective` liveness) once combat lifts — so the row never shifts mid-fight. Pinned: combat tick leaves width at 188 with the icon hidden; exit applies 150.

## 3. Pin updates (owned; extend-never-weaken holds)

New §18 (23 checks): druid end-to-end with the real provider (no stubbing) — first paint already 6-wide (226), TF/Berserk `last_hidden == true`, Mangle `false`, icons hidden, survivors shifted; a further tick runs 8 providers exactly once with a stable row. Fresh paladin row with a stubbed `{ hidden = true }` CS — hide closes to 150 with judgement at offset 0, revive restores 188/38, combat defers (pending latch, geometry held) and exit applies.

Moved pins (2, both with rationale comments — the brief's anticipated "width/count move"):
- §15 druid creation width `8 * 36 + 7 * 2` (302) → `6 * 36 + 5 * 2` (226).
- §18's own draft creation pin, same values.
- Reason (found during implementation, verified by probe): `apply_settings` ends with `update_display` when the row should show, so the creation paint already observes the dead TF/Berserk probes and reflows — there is no "wanted-only" intermediate state to pin. No other existing pin moved: paladin/hunter/warrior/shaman providers never return hidden in-sandbox, so their rows are untouched.

## 4. Evidence

- `lua5.1 tests/hud_state.lua`: **PASS 424 checks** (401 before + 23 new; 0 failures).
- Full harness: **35 steps, 0 failed** (baseline at dispatch was already 35/0 — the reconcile wave had landed).
- `luacheck hud.lua tests/hud_state.lua`: **0 warnings / 0 errors** (tree total 2 warnings / 0 errors, same two pre-existing other-lane files as baseline).
- **Mutation proofs on a /tmp/opencode full copy (removed after; repo diffed CLEAN):**
  1. Reflow suppression (post-loop `HUD.reflow_row` call neutralised) → 5 FAILs: druid + §18 widths return to the 302 gap, paladin row stays 188/38. Restored → 424 PASS.
  2. Combat-deferral bypass (lockdown guards removed) → 2 FAILs: pending latch never sets, geometry shifts mid-fight (150 in combat). Restored → 424 PASS, copy byte-identical (`diff -q` clean).

## 5. UNCONFIRMED / in-client checks (offline cannot load the addon)

Row gap closure with a genuinely dead slot in-client (runeless-Era Mangle, absent-TF client), revive on rune equip / spell-data arrival, no visible row shift when a flip lands during combat with the deferred apply on combat exit, glow-stop timing on the hidden icon. In-client session owns these.

Cross-references: `desks/hud/journal.md`, `desks/hud/.signals/20261017T152131Z.json`, `bench/buildout_hud-grade_2026-10-17.md` §5 finding #2 (closed here), `bench/briefs/brief_hud-reflow_2026-10-17.md`.
