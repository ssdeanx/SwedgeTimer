# Hunter Weave-Prog — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the filed hunter weave-prog live wiring + widget (bench/hunter_weave_distance_2026-10-19.md prog spec): compat speed/dir probes, options widget, hunter prog wiring + pins.
- **Scope:** ONLY compat.lua (speed/dir probes), classes/hunter.lua (prog wiring), option_tables.lua + config_presets.lua (ONE widget + default), tests/hunter_state.lua, tests/secret_guard_state.lua, tests/options_load_state.lua.
- **Out of scope:** guides, other class files, bars, hud.lua, practice, main, diag, guide_contract, run.sh, TOCs, README, docs, versions; no H2 lust; no TBC Steady re-point; no multi-target; no git; no invented ids.
- **Next step:** implement per prog spec; pins in the three suites; harness + luacheck floor + mutations on /tmp/opencode copies.

## 2026-10-19 — Prog live end-to-end, pins green
- **Worked on:** compat `api.GetUnitSpeed` (current speed, secret-safe, nil unknown) + `api.IsPlayerMoving` (boolean, nil unknown); hunter `ST.HUNTER.step_weave_prog` (pure, spec-verbatim priority: re-anchor > snap > hold > integrate + backpedal flip) + `ST.HUNTER.update_weave_prog` (toggle-gated, driven from on_bar_update, combat-exit clear); ONE toggle `hunter_weave_prog_enabled` at 4.2 (nil = off, no default line — documented in the nil-off comment); pins: hunter_state Sec 20c/20d (~70 checks), secret_guard R11 (22 checks), options_load Hunter key (toggle+order+getter+no-true-default).
- **Decision (supersedes spec loudly):** no client API exposes a forward/backward sign, so "movement sign" is carried integrator state (dir, default +1, flipped in the <4.6 band), NOT a client probe. Target motion = target GetUnitSpeed > 0. IsPlayerMoving serves only the still-fill (unknown speed + confirmed still = 0); unknown motion never 0-fills. Combat-exit clears prog (per-fight state; a stale stamp would slam the next pull to a limit).
- **Caught during work:** opts closures cannot see the `local sb` being assigned (global nil swallowed by compat pcall) — secret_guard R11 fixtures use pre-declared holders; same trap avoided in hunter_state. Chose control speed 6: suite flags 7 as SECRET_CD_ENABLED.
- **Current state:** Harness 38/0, luacheck 2/0 (floor held; 9 self-introduced test warnings repaired). 8/8 mutations killed on /tmp/opencode copies (removed after). Filed-state pins hold (no IsItemInRange/item:8149/C_Spell/CLEU in hunter scope).
- **Next step:** Orchestrator validates. IN-CLIENT OWED: prog dynamics (operator-reported, wago JS shell), GetUnitSpeed availability per family (esp. TBC 2.5.6), widget display lane (bar/50% tick) still unbuilt.
