# Brief: feature-hunter-audit (2026-10-19)

## Objective
Read-only error-path audit of the current feature set for casual + top-level play where split-second reaction matters. Hunt swallowed failures, misleading fallbacks, weak diagnostics, hidden retry exhaustion. Produce `bench/feature_hunter_audit_2026-10-19.md`.

## Scope (read-only)
- Audit surface (read, do not edit): `main.lua`, `bars.lua`, `compat.lua`, `swing_source.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `nextaction_ui.lua`, `classes/druid.lua`, `classes/hunter.lua`, `classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua`, `hud.lua`, `practice.lua`, `enemy_swing.lua`, `weave_range.lua`, `diag.lua`. Reference paths/lines — do not paste file contents.
- Focus: swing timing paths, twist window band + attempt/success scoring, weave breakpoint marker + cast spark, next-action guide decisions, HUD refresh, range/GCD/latency fallbacks, Retail stand-in + Forever PLAYER_SWING engine, 5s init deadline path, combat-exit teardown (HU-4 fix), secret-value restrictions (Midnight watch).

## Context (read first)
- `desks/journal.md` (Status + Lanes — all lanes done, 35 steps 0 failed, luacheck 2/0 floor), `bench/lessons.md`, `bench/oracle_audit_2026-10-17.md`, `bench/verify_bank.md`, `hands-up.md` (HU-1..HU-4). No re-deriving answered questions — extend or supersede loudly.

## Method
- Trace each timing-critical path to its failure mode: what happens when the event never arrives, arrives late, or lies (nil lib tables on Cata/Mists per AGENTS.md, missing swing on Retail, probe-gated Forever events, aura poll fallback on TBC).
- Rank findings by reaction-time impact (ms-scale) and player tier (casual vs top-level). Each finding: location (file:line), failure mode, worst-case player-visible effect, evidence (harness/log/trace or UNCONFIRMED), suggested next probe (not a fix).
- Standing rules: no code edits, no git, no lint-config changes. Preserve endings (read-only anyway). Mutation proofs only on /tmp/opencode copies if you run probes.

## Boundary
- READ-ONLY except one new bench file + own desk journal/signals. Do NOT write addon code. Do NOT overlap with proctor lane (hunter = error paths/diagnostics; proctor = coverage/gaps). If you spot a coverage gap, log it as one line and leave it for proctor.
- Output: `bench/feature_hunter_audit_2026-10-19.md` (NEW file). Never overwrite existing bench files.

## Workshop mechanics (mandatory)
1. `bench-read`: journals before artifacts.
2. `desk-open`: ensure `desks/feature-hunter/` exists; resume if live.
3. `desk-journal`: append entry at end.
4. `signal-write`: emit `done` JSON + journal marker.

## Validation owner
- Orchestrator reconciles against proctor findings; checks every finding has file:line + evidence label (proven offline / UNCONFIRMED) + tier/impact rank.
