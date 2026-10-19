# hunter — Journal

## 2026-10-17 — Desk opened
- **Purpose:** H1/H2/H4/H6 + safe-to-move indicator + readiness/feign handling.
- **Scope:** classes/hunter.lua and hunter support files only.
- **Next step:** wait for dispatch brief in bench/briefs/; corrections from bench/verify_bank.md apply (H3 manual-toggle fallback).

## 2026-10-17 — Build-out round 1 done (offline-verified)
- **Worked on:** finished the mid-flight partial (kept hunter_window.hold_seconds; kept hunter_guide's rule 2b + H2 lust suppression) and built the rest:
  - **H1** `hold_seconds` now feeds the cast-bar window face label (kernel-backed HOLD seconds); header list + 17 new window-suite checks.
  - **H2** gather wiring in classes/hunter.lua: `st.api.scan_player_aura` over compat's confirmed 2825/32182, family-gated on `st.lust_supported` (Era never arms), 0.5 s throttle (`hunter_lust_at`/`hunter_lust_remaining`); engine suppression (rules 6a/6b, Steady spam cue) already in hunter_guide.lua and now pinned.
  - **H4** rule 2b (nil=allow, byte-exact 0=HOLD ahead of every cast prompt) pinned with 16 checks.
  - **H6** BW duration badge + pet Frenzy stacks badges in hunter_ui.lua (ids 19574/19615, wowhead-cited; countdown rule, gold glow ≤4 s, stack text; option-gated nil=off).
  - **Safe-to-move** cast zone + threshold marker on the ranged visuals frame via `is_stopped_position_safe` (green/red ladder, option-gated nil=off).
  - **FD** 5384 clears the class-owned ranged display state; **Readiness** 23989 forces the RF scan throttle (`hunter_ui.force_rapid_fire_refresh`).
  - Tests: +138 checks across the three hunter suites (1571 → 1709).
- **Current state:** offline-verified. `hunter_state` 448 / `hunter_window_state` 213 / `hunter_guide_state` 1048, all green; luacheck 0 errors (the 7 touched files 0 warnings). Mutation proofs on /tmp/opencode/mut_hunter (5 mutations, all caught, files restored byte-identical). Full harness at hand-off: hunter steps green; smoke/bars_state/hud_state/designmode_state fail from OTHER lanes' in-flight work (druid.lua crash, paladin/warrior/druid count drift, bars.lua register_zone) — the HUNTER rows in bars_state are the expected new widget counts (frames 20/18, textures 23/17, fontstrings 13/11), reconciled in the later wave.
- **Next step:** in-client checks (list in bench/buildout_hunter_2026-10-17.md): BW 19574/Frenzy 19615/Readiness 23989/FD 5384 reads, Bloodlust aura scan on TBC, cast-zone movement colours, badge geometry. Options pass wires `hunter_cast_zone_enabled` / `hunter_bw_badge_enabled` / `hunter_frenzy_stacks_enabled` (all nil=off today) + H3's manual multi-target toggle.
